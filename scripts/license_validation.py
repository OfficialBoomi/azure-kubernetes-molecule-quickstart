import sys
import logging
import requests
import urllib3

logger = logging.getLogger(__name__)


def _create_auth_headers(username, password):
    headers = {"Content-Type": "application/json", "Accept": "application/json"}
    headers.update(urllib3.util.make_headers(basic_auth=f"{username}:{password}"))
    return headers


def _verify_boomi_licensing(username, password, account):
    _headers = _create_auth_headers(username, password)
    API_URL = f"https://api.boomi.com/api/rest/v1/{account}/Account/{account}"
    resp = requests.get(API_URL, headers=_headers)
    resp.raise_for_status()
    json_resp = resp.json()

    account_status = json_resp["status"]
    enterprise_licenses_purchased = json_resp["licensing"]["enterprise"]["purchased"]
    enterprise_licenses_used = json_resp["licensing"]["enterprise"]["used"]

    # Is the account active?
    if account_status == "active":
        logger.info(f"Account is active")
    else:
        logger.error("Exception: Boomi account is inactive")
        raise Exception(f"Boomi account {account} is inactive.")

    # Do we have license entitlements at all?
    if enterprise_licenses_purchased > enterprise_licenses_used:
        logger.info(
            f"Licenses are available - Purchased: {enterprise_licenses_purchased} / Used: {enterprise_licenses_used}"
        )
    else:
        logger.error("Exception: No enterprise license available")
        raise Exception(
            f"No enterprise licenses for account {account} are available. Purchased: {enterprise_licenses_purchased}, Used: {enterprise_licenses_used}"
        )


def _generate_install_token(username, password, account_id, token_type, timeout):
    REQ_TOKEN_TYPES = ["MOLECULE"]
    if token_type.upper() not in REQ_TOKEN_TYPES:
        raise Exception(f"Parameter TokenType must be one of: {str(REQ_TOKEN_TYPES)}")

    _headers = _create_auth_headers(username, password)
    API_URL = f"https://api.boomi.com/api/rest/v1/{account_id}/InstallerToken/"
    payload = {"installType": token_type, "durationMinutes": int(timeout)}
    logger.info(payload)
    resp = requests.post(API_URL, headers=_headers, json=payload)
    resp.raise_for_status()
    rj = resp.json()

    return rj["token"]


def auth_and_licensing_logic(username, password, account_id, token_type, token_timeout):
    # Verify licensing
    _verify_boomi_licensing(username, password, account_id)
    if username.startswith("BOOMI_TOKEN."):
        # Generate install token
        token = _generate_install_token(
            username, password, account_id, token_type, token_timeout
        )
        return token


if __name__ == "__main__":
    STATUS = "SUCCESS"
    molecule_token = None
    try:
        BoomiAccountID = sys.argv[1]
        BoomiUsername = sys.argv[2]
        BoomiPassword = sys.argv[3]
        TokenType = sys.argv[4]
        TokenTimeout = sys.argv[5]

        molecule_token = auth_and_licensing_logic(BoomiUsername, BoomiPassword, BoomiAccountID, TokenType.upper(), TokenTimeout)

    except requests.exceptions.RequestException as err:
        logging.error(err)
        STATUS = "FAILED"
    except Exception as err:
        logging.error(err)
        STATUS = "FAILED"
    finally:
        print("status:{},token:{}".format(STATUS,molecule_token))
