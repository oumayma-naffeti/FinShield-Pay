import base64
import json
import logging
import os
import re
import time
import uuid
from decimal import Decimal, InvalidOperation
from functools import wraps

import boto3
from boto3.dynamodb.conditions import Key
from botocore.exceptions import ClientError
from flask import Flask, jsonify, request

TABLE_NAME = os.environ.get("TABLE_NAME", "finshield-transactions")
REGION = os.environ.get("AWS_REGION") or os.environ.get("AWS_DEFAULT_REGION", "us-east-1")
CLIENT_ID = os.environ.get("COGNITO_CLIENT_ID")  # optionnel
ISSUER = os.environ.get("COGNITO_ISSUER")        # optionnel

# Seuls ces numeros de TEST sont acceptes. Un controle de Luhn ne prouve pas
# qu'un numero est un numero de test : on utilise donc une liste fermee.
CARTES_TEST = {
    "4242424242424242": "accepted",
    "4000000000000002": "declined",
}

ORDER_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")

logging.basicConfig(level=logging.INFO, format="%(message)s")
log = logging.getLogger("finshield")

table = boto3.resource("dynamodb", region_name=REGION).Table(TABLE_NAME)

app = Flask(__name__)
app.config["MAX_CONTENT_LENGTH"] = 4096


def log_event(event, **fields):
    # Jamais de numero de carte, de jeton ni de secret dans les journaux.
    log.info(json.dumps({"ts": int(time.time()), "event": event, **fields}))


def merchant_from_token():
    """Identite du marchand, tiree du jeton deja valide par API Gateway.

    L'ALB est interne : seul le VPC Link peut l'atteindre. Les taches n'ont pas
    d'acces Internet, donc la signature n'est pas reverifiee ici ; on controle
    en revanche le type, l'expiration, l'audience et l'emetteur.
    """
    header = request.headers.get("Authorization", "")
    if not header.startswith("Bearer "):
        return None
    parts = header[7:].split(".")
    if len(parts) != 3:
        return None
    try:
        payload = parts[1] + "=" * (-len(parts[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload))
    except ValueError:
        return None
    if not isinstance(claims, dict):
        return None
    sub = claims.get("sub")
    if not isinstance(sub, str) or not sub:
        return None
    if claims.get("token_use") != "id":
        return None
    exp = claims.get("exp")
    if not isinstance(exp, (int, float)) or exp <= time.time():
        return None
    if CLIENT_ID and claims.get("aud") != CLIENT_ID:
        return None
    if ISSUER and claims.get("iss") != ISSUER:
        return None
    return sub


def require_merchant(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        merchant = merchant_from_token()
        if not merchant:
            return jsonify(error="non autorise"), 401
        return fn(merchant, *args, **kwargs)

    return wrapper


def parse_payment(body):
    """Valide la demande. Les champs inconnus (dont merchant_id) sont ignores."""
    if not isinstance(body, dict):
        return None, "corps JSON attendu"

    order_ref = body.get("order_ref")
    if not isinstance(order_ref, str) or not ORDER_RE.match(order_ref):
        return None, "order_ref invalide (1 a 64 caracteres : lettres, chiffres, - et _)"

    try:
        amount = Decimal(str(body.get("amount")))
    except InvalidOperation:
        return None, "montant invalide"
    if not amount.is_finite() or amount <= 0 or amount > Decimal("10000"):
        return None, "montant hors limites (0 exclu, 10000 maximum)"
    amount = amount.quantize(Decimal("0.01"))
    if amount <= 0:
        return None, "montant trop petit"

    card = body.get("card_number")
    if not isinstance(card, str):
        return None, "carte invalide"
    card = re.sub(r"[ -]", "", card)
    if card not in CARTES_TEST:
        return None, "carte de test non autorisee"

    return {
        "order_ref": order_ref,
        "amount": str(amount),
        "card_last4": card[-4:],
        "status": CARTES_TEST[card],
    }, None


def public(item):
    """Vue renvoyee au marchand : aucune donnee de carte, pas d'identifiant interne."""
    return {
        "transaction_id": item["transaction_id"],
        "order_ref": item["order_ref"],
        "amount": item["amount"],
        "currency": item["currency"],
        "status": item["status"],
        "card_last4": item["card_last4"],
        "created_at": item["created_at"],
    }


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.post("/api/payments")
@require_merchant
def create_payment(merchant):
    data, err = parse_payment(request.get_json(silent=True))
    if err:
        log_event("payment_rejected", reason=err)
        return jsonify(error=err), 400

    item = {
        "merchant_id": merchant,  # vient du jeton, jamais du corps de la requete
        "order_ref": data["order_ref"],
        "transaction_id": "txn_" + uuid.uuid4().hex,
        "amount": data["amount"],
        "currency": "TND",
        "status": data["status"],
        "card_last4": data["card_last4"],
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }

    try:
        # Ecriture conditionnelle : une seule transaction par (marchand, commande)
        table.put_item(Item=item, ConditionExpression="attribute_not_exists(order_ref)")
    except ClientError as exc:
        code = exc.response["Error"]["Code"]
        if code != "ConditionalCheckFailedException":
            log_event("dynamodb_error", code=code)
            return jsonify(error="erreur interne"), 500
        existing = table.get_item(
            Key={"merchant_id": merchant, "order_ref": data["order_ref"]}
        ).get("Item")
        if not existing:
            return jsonify(error="erreur interne"), 500
        if existing["amount"] != data["amount"]:
            log_event("payment_conflict", order_ref=data["order_ref"])
            return jsonify(error="order_ref deja utilise avec un autre montant"), 409
        log_event("payment_replayed", order_ref=data["order_ref"])
        return jsonify(**public(existing), idempotent=True), 200

    log_event("payment_created", order_ref=data["order_ref"], status=data["status"])
    return jsonify(**public(item), idempotent=False), 201


@app.get("/api/payments")
@require_merchant
def list_payments(merchant):
    # La cle de partition est l'identite du marchand : il ne voit que ses lignes.
    resp = table.query(KeyConditionExpression=Key("merchant_id").eq(merchant), Limit=50)
    return jsonify(items=[public(i) for i in resp.get("Items", [])])


@app.get("/api/payments/<order_ref>")
@require_merchant
def get_payment(merchant, order_ref):
    if not ORDER_RE.match(order_ref):
        return jsonify(error="order_ref invalide"), 400
    item = table.get_item(Key={"merchant_id": merchant, "order_ref": order_ref}).get("Item")
    if not item:
        return jsonify(error="introuvable"), 404
    return jsonify(public(item))


@app.errorhandler(413)
def too_large(_):
    return jsonify(error="requete trop volumineuse"), 413


@app.errorhandler(404)
def not_found(_):
    return jsonify(error="introuvable"), 404


@app.errorhandler(405)
def not_allowed(_):
    return jsonify(error="methode non autorisee"), 405