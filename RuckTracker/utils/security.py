import hashlib
import hmac
import os


def salted_ip_hash(ip: str | None) -> str:
    """Return a salted, hex-encoded hash for an IP-like string.

    Stores only a hash; never the raw IP. Uses HMAC-SHA256 with IP_HASH_SALT.
    """
    if not ip:
        ip = "unknown"
    salt = os.environ.get("IP_HASH_SALT", "fallback_salt_change_me")
    digest = hmac.new(salt.encode("utf-8"), ip.encode("utf-8"), hashlib.sha256).hexdigest()
    return digest

