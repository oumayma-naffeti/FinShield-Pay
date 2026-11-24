import os
import mimetypes
import base64
import boto3

from botocore.exceptions import ClientError
from urllib.parse import unquote

s3 = boto3.client("s3")
BUCKET = os.environ["BUCKET_NAME"]


def handler(event, context):
    parameters = event.get("pathParameters") or {}
    path = unquote(parameters.get("proxy") or "").lstrip("/")

    if not path:
        path = "index.html"

    parts = path.split("/")

    if any(part in ("", ".", "..") for part in parts) or "\\" in path:
        return response(400, "Chemin invalide")

    try:
        obj = s3.get_object(Bucket=BUCKET, Key=path)
        content = obj["Body"].read()

        content_type = (
            obj.get("ContentType")
            or mimetypes.guess_type(path)[0]
            or "application/octet-stream"
        )

        is_binary = not (
            content_type.startswith("text/")
            or content_type in (
                "application/javascript",
                "application/json",
                "image/svg+xml"
            )
            or content_type.endswith("+json")
        )

        body = (
            base64.b64encode(content).decode("ascii")
            if is_binary
            else content.decode("utf-8")
        )

        return {
            "statusCode": 200,
            "headers": {
                "Content-Type": content_type,
                "X-Content-Type-Options": "nosniff",
                "Cache-Control": "no-cache"
            },
            "isBase64Encoded": is_binary,
            "body": body
        }

    except ClientError as error:
        code = error.response.get("Error", {}).get("Code", "")

        if code in ("NoSuchKey", "404", "NotFound"):
            return response(404, "Fichier introuvable")

        print("Erreur S3 :", code)
        return response(500, "Erreur interne du serveur")

    except Exception as error:
        print("Erreur frontend :", type(error).__name__)
        return response(500, "Erreur interne du serveur")


def response(status, message):
    return {
        "statusCode": status,
        "headers": {
            "Content-Type": "text/plain; charset=utf-8",
            "X-Content-Type-Options": "nosniff",
            "Cache-Control": "no-store"
        },
        "body": message
    }
