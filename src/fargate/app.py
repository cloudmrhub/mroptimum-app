#!/usr/bin/env python3
import os
import sys
import json
import boto3
import shutil
from pynico_eros_montin import pynico as pn

def sanitize_for_json(data):
    if isinstance(data, dict):
        return {k: sanitize_for_json(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [sanitize_for_json(v) for v in data]
    elif isinstance(data, (int, float, str, bool, type(None))):
        return data
    else:
        return str(data)

def write_json_file(file_path, data):
    try:
        sanitized_data = sanitize_for_json(data)
        with open(file_path, 'w', encoding='utf-8') as file:
            json.dump(sanitized_data, file, indent=4)
        print(f"JSON data successfully written to {file_path}")
    except Exception as e:
        print(f"Failed to write JSON data to file: {e}")

def s3FileTolocal(J, s3=None, pt="/tmp"):
    key = J["key"]
    bucket = J["bucket"]
    filename = J["filename"]
    if s3 is None:
        s3 = boto3.resource("s3")
    O = pn.Pathable(pt)
    O.addBaseName(filename)
    O.changeFileNameRandom()
    f = O.getPosition()
    s3.Bucket(bucket).download_file(key, f)
    J["filename"] = f
    J["type"] = "local"
    return J

def process_event(event):
    # Connect to S3
    s3 = boto3.resource("s3")
    
    # Get S3 info from the event
    bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
    file_key = event["Records"][0]["s3"]["object"]["key"]
    print(f"Processing file {file_key} from bucket {bucket_name}")

    # Download file locally
    fj = pn.createRandomTemporaryPathableFromFileName("a.json")
    s3.Bucket(bucket_name).download_file(file_key, fj.getPosition())
    print(f"File downloaded to {fj.getPosition()}")
    
    # Read JSON file and process it
    J = pn.Pathable(fj.getPosition()).readJson()
    print("JSON file read")

    pipelineid = J.get("pipeline")
    token = J.get("token")
    OUTPUT = J.get("output", {})
    
    # Determine options based on OUTPUT flags
    savecoils = "--no-coilsens"
    savematlab = "--no-matlab"
    savegfactor = "--no-gfactor"
    if OUTPUT.get("coilsensitivity"):
        savecoils = "--coilsens"
    if OUTPUT.get("matlab"):
        savematlab = "--matlab"
    if OUTPUT.get("gfactor"):
        savegfactor = "--gfactor"
    
    print(f"Options: {savecoils}, {savematlab}, {savegfactor}")
    
    T = J["task"]
    # Download referenced S3 files if needed:
    if T["options"]["reconstructor"]["options"]["noise"]["options"]["type"] == "s3":
        T["options"]["reconstructor"]["options"]["noise"]["options"] = s3FileTolocal(
            T["options"]["reconstructor"]["options"]["noise"]["options"], s3)
    if T["options"]["reconstructor"]["options"]["signal"]["options"]["type"] == "s3":
        T["options"]["reconstructor"]["options"]["signal"]["options"] = s3FileTolocal(
            T["options"]["reconstructor"]["options"]["signal"]["options"], s3)
    
    # Write updated JSON structure for processing
    JO = pn.createRandomTemporaryPathableFromFileName("a.json")
    T["token"] = token
    T["pipelineid"] = pipelineid
    JO.writeJson(T)
    
    # Setup output directory and log file paths
    O = pn.createRandomTemporaryPathableFromFileName("a.json")
    O.appendPath("OUT")
    O.ensureDirectoryExistence()
    OUT = O.getPosition()
    log_path = pn.createRandomTemporaryPathableFromFileName("a.json").getPosition()
    
    # Run the heavy processing command
    K = pn.BashIt()
    K.setCommand(f"python -m mrotools.snr -j {JO.getPosition()} -o {OUT} --parallel {savematlab} {savecoils} {savegfactor} --no-verbose -l {log_path}")
    print(f"Running command: {K.getCommand()}")
    K.run()
    
    # Check log for errors (example)
    g = pn.Log()
    g.appendFullLog(log_path)
    if g.log[-1].get("what") == "ERROR":
        print("ERROR in the computation")
        sys.exit(1)
    
    # Zip the output and upload to the results bucket
    Z = pn.createRandomTemporaryPathableFromFileName("a.zip")
    Z.ensureDirectoryExistence()
    shutil.make_archive(Z.getPosition()[:-4], "zip", O.getPath())
    
    # Read bucket names from environment variables (set in Task Definition)
    mroptimum_result = os.getenv("ResultsBucketName")
    s3.Bucket(mroptimum_result).upload_file(Z.getPosition(), Z.getBaseName())
    print("Result uploaded successfully")
    
    # Optionally, return some status or output
    return

def main():
    # Read event from an environment variable provided via Step Functions (FILE_EVENT)
    event_str = os.environ.get("FILE_EVENT")
    if not event_str:
        print("No event input provided!")
        sys.exit(1)
    try:
        event = json.loads(event_str)
    except Exception as e:
        print("Invalid JSON input:", e)
        sys.exit(1)
    
    process_event(event)

if __name__ == "__main__":
    main()
