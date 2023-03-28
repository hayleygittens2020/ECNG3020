import requests
import json
from requests_oauthlib import OAuth2Session
from oauthlib.oauth2 import MobileApplicationClient

client_id = "81d57aa5-5e0e-470b-8b37-a69efe48288a"
scopes = ['Sites.ReadWrite.All','Files.ReadWrite.All']
auth_url = 'https://login.microsoftonline.com/aae862ee-56a9-48cb-ac59-11922bb9b864/oauth2/v2.0/authorize'

#OAuth2Session is an extension to requests.Session
#used to create an authorization url using the requests.Session interface
#MobileApplicationClient is used to get the Implicit Grant

oauth = OAuth2Session(client=MobileApplicationClient(client_id=client_id), scope=scopes)
authorization_url, state = oauth.authorization_url(auth_url)
consent_link = oauth.get(authorization_url)
print(consent_link.url)