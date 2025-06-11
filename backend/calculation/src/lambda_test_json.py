import json
import os
import boto3
from app import handler
import pynico_eros_montin.pynico as pn
E=pn.Pathable("backend/calculation/ac_brain_multislice.json")
E=E.readJson()
import sys
import cmtools.cmaws as cmaws

        
LOGIN=pn.Pathable('/g/key.json').readJson()
KID=LOGIN['key_id']
KSC=LOGIN['key']
TOK=LOGIN['token']

s3 = cmaws.getS3Resource(KID,KSC,TOK)


handler(E, None,s3=s3)