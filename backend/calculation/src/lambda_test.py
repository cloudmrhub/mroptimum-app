import json
import os
import boto3
from app import handler
import pynico_eros_montin.pynico as pn
E=pn.Pathable("backend/calculation/event.json")
E=E.readJson()
import sys
import cmtools.cmaws as cmaws


def list_bucket(bucket_name,s3):
    # Check if the bucket exists and list its contents
    bucket = s3.Bucket(bucket_name)
    OBJ=[]
    if bucket.creation_date:
        print(f"Bucket '{bucket_name}' exists. Listing contents:")
        for obj in bucket.objects.all():
            OBJ.append(obj.key)
    else:
        print(f"Bucket '{bucket_name}' does not exist.")
    return OBJ

        
LOGIN=pn.Pathable('/g/key.json').readJson()
KID=LOGIN['key_id']
KSC=LOGIN['key']
TOK=LOGIN['token']

s3 = cmaws.getS3Resource(KID,KSC,TOK)




handler(E, None,s3=s3)