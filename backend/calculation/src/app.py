#!/usr/bin/env python3
import json
import boto3
import os
import shutil
import sys
from pynico_eros_montin import pynico as pn

def sanitize_for_json(data):
    """Recursively sanitize data to make it JSON-serializable."""
    if isinstance(data, dict):
        return {k: sanitize_for_json(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [sanitize_for_json(v) for v in data]
    elif isinstance(data, (int, float, str, bool, type(None))):
        return data
    else:
        return str(data)

def write_json_file(file_path, data):
    """Sanitize `data` and write it as JSON to `file_path`."""
    try:
        sanitized_data = sanitize_for_json(data)
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(sanitized_data, f, indent=4)
        print(f"JSON data successfully written to {file_path}")
    except Exception as e:
        print(f"Failed to write JSON data to file: {e}")

def s3FileTolocal(J, s3=None, pt="/tmp"):
    """
    If J == {"bucket": ..., "key": ..., "filename": ...}, download that S3 object
    into a random file under `pt`, then set J["filename"] to the local path and
    J["type"] = "local". Return the modified J.
    """
    key = J["key"]
    bucket = J["bucket"]
    filename = J["filename"]
    if s3 is None:
        s3 = boto3.resource("s3")
    O = pn.Pathable(pt)
    O.addBaseName(filename)
    O.changeFileNameRandom()
    local_path = O.getPosition()
    s3.Bucket(bucket).download_file(key, local_path)
    J["filename"] = local_path
    J["type"] = "local"
    return J

def do_process(event, context=None, s3=None):
    """
    Core logic that:
      1. Creates a pn.Log for tracing.
      2. Downloads the incoming JSON from S3.
      3. Parses pipeline/task/options flags.
      4. Downloads any referenced S3 files (noise/signal) locally.
      5. Runs `python -m mrotools.snr …`.
      6. If successful: zip “OUT” and upload to `ResultsBucketName`.
      7. On error: collect logs, write error files, zip “OUT” and upload to `FailedBucketName`.
      8. Return a dict suitable for AWS Lambda (statusCode/body).
    """
    # Read bucket names from environment (set in Lambda config or Fargate Task Definition)
    mroptimum_result = os.getenv("ResultsBucketName", "mrorv2")
    mroptimum_failed = os.getenv("FailedBucketName", "mrofv2")

    # Initialize logging
    L = pn.Log("mroptimum job", {"event": event, "context": context or {}})

    try:
        # Prepare S3 resource
        if s3 is None:
            s3 = boto3.resource("s3")

        #s3 implementation
        if "Records" in event and event["Records"] and "s3" in event["Records"][0]:
            # ----- S3 path: extract bucket/key, download JSON -----
            bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
            file_key    = event["Records"][0]["s3"]["object"]["key"]
            L.append(f"bucket_name {bucket_name}")
            L.append(f"file_key {file_key}")

            # Download the JSON payload to /tmp/<random>.json
            fj = pn.createRandomTemporaryPathableFromFileName("a.json")
            s3.Bucket(bucket_name).download_file(file_key, fj.getPosition())
            L.append(f"file downloaded to {fj.getPosition()}")

            # Read that JSON from local
            J = pn.Pathable(fj.getPosition()).readJson()
            L.append("json file read")
        else:
            # no S3 event, assume direct payload
            L.append("no S3 event, using direct payload")
            J = event
            L.append("using direct payload from API")
            # If you want to preserve the "alias" or "pipeline" in logs:
            if "alias" in J:
                L.append(f"alias {J.get('alias')}")
            if "pipeline" in J:
                L.append(f"pipeline {J.get('pipeline')}")

        # ───────────────────────────────────────────────
        # 2) Extract pipelineid, token, OUTPUT flags from J
        # ───────────────────────────────────────────────
        pipelineid = J.get("pipeline",None)
        token      = J.get("token",None)
        OUTPUT     = J.get("output", {})
        L.append(f"pipelineid {pipelineid}")
        L.append(f"token {token}")

        # Determine flags for coilsensitivity, matlab, gfactor
        savecoils  = "--no-coilsens"
        savematlab = "--no-matlab"
        savegfactor= "--no-gfactor"
        if OUTPUT.get("coilsensitivity"):
            savecoils = "--coilsens"
        if OUTPUT.get("matlab"):
            savematlab = "--matlab"
        if OUTPUT.get("gfactor"):
            savegfactor = "--gfactor"
        L.append(f"savecoils {savecoils}")
        L.append(f"savematlab {savematlab}")
        L.append(f"savegfactor {savegfactor}")

        # 5) Get the task dict
        T = J["task"]
        NOISE_AVAILABLE=False
        SIGNAL_AVAILABLE=False
        MULTIRAID= False
        # 6) If noise or signal == S3 type, download locally
        recon_opts = T["options"]["reconstructor"]["options"]
        try:
            noise_opts  = recon_opts["noise"]["options"]
            if noise_opts.get("type") == "s3":
                T["options"]["reconstructor"]["options"]["noise"]["options"] = s3FileTolocal(noise_opts, s3)
                L.append("noise file downloaded locally")   
                NOISE_AVAILABLE = True 
        except:
            # If "noise" is not present, we skip this step
            L.append("no noise options found, skipping download")
            
        try:
            signal_opts = recon_opts["signal"]["options"]        
            if signal_opts.get("type") == "s3":
                T["options"]["reconstructor"]["options"]["signal"]["options"] = s3FileTolocal(signal_opts, s3)
                L.append("signal file downloaded locally")
                SIGNAL_AVAILABLE = True
                if "vendor" in T["options"]["reconstructor"]["options"]["signal"]["options"]:
                    if T["options"]["reconstructor"]["options"]["signal"]["options"]["vendor"].lower() == "siemens":
                        # If vendor is mroptimum, we can use the signal options directly
                        L.append("signal vendor is mroptimum, using options directly")
                        MULTIRAID= T["options"]["reconstructor"]["options"]["signal"]["options"].get("multiraid", False)
                    
        except:
            # If "signal" is not present, we skip this step
            L.append("no signal options found, skipping download")
            

        # 7) Write updated T → /tmp/<random>.json for mrotools.snr
        JO = pn.createRandomTemporaryPathableFromFileName("a.json")
        T["token"] = token
        T["pipelineid"] = pipelineid
        JO.writeJson(T)
        L.append(f"writeJson for mrotools input: {JO.getPosition()}")

        # 8) Prepare output folder under /tmp: /tmp/<random>/OUT
        O = pn.createRandomTemporaryPathableFromFileName("a.json")
        O.appendPath("OUT")
        O.ensureDirectoryExistence()
        OUT = O.getPosition()
        L.append(f"output dir set to {OUT}")

        # 9) Prepare a logfile path
        log_path = pn.createRandomTemporaryPathableFromFileName("a.json").getPosition()

        # 10) Run the mrotools.snr command
        K = pn.BashIt()
        # In Lambda we do “--no-parallel” because CPU cores are limited; 
        # in Fargate you can remove that flag or change to “--parallel” if desired. 
        # Here we keep it as “--no-parallel” by default, but you can override via ENV if needed.
        parallel_flag = os.getenv("MROPARALLEL", "false").lower()
        if parallel_flag in ("true", "1", "yes"):
            parallel_arg = "--parallel"
        else:
            parallel_arg = "--no-parallel"
            
        # check noise and signal availability
        if (NOISE_AVAILABLE or MULTIRAID ) and SIGNAL_AVAILABLE:
            L.append("noise and signal available, proceeding with computation")
        else:
            L.append("WARNING: noise or signal not available, using --no-parallel")
            raise Exception("Noise or signal not available, cannot proceed with computation")

        cmd = (
            f"python -m mrotools.snr "
            f"-j {JO.getPosition()} "
            f"-o {OUT} "
            f"{parallel_arg} {savematlab} {savecoils} {savegfactor} "
            f"--no-verbose "
            f"-l {log_path}"
        )
        K.setCommand(cmd)
        L.append(f"running command: {cmd}")
        K.run()

        # 11) Inspect the generated log for errors
        g = pn.Log()
        g.appendFullLog(log_path)
        if g.log and g.log[-1].get("what") == "ERROR":
            # If the final log entry says “ERROR”, treat as a computation failure
            L.append("ERROR in the computation")
            L.appendFullLog(log_path)
            raise Exception("ERROR in the computation")

        L.append("computation completed successfully")
        L.appendFullLog(log_path)

        # 12) Zip the entire OUT folder
        Z = pn.createRandomTemporaryPathableFromFileName("a.zip")
        Z.ensureDirectoryExistence()
        base = Z.getPosition()[:-4]  # strip “.zip”
        shutil.make_archive(base, "zip", O.getPath())
        zip_path = Z.getPosition()
        L.append(f"zipped output to {zip_path}")

        # 13) Upload zip to the “results” bucket
        s3.Bucket(mroptimum_result).upload_file(zip_path, Z.getBaseName())
        L.append(f"uploaded results → s3://{mroptimum_result}/{Z.getBaseName()}")

        # 14) Return success (Lambda will interpret this as a 200)
        return {
            "statusCode": 200,
            "body": json.dumps({
                "results": {
                    "key": Z.getBaseName(),
                    "bucket": mroptimum_result
                }
            })
        }

    except Exception as e:
        # On *any* exception, bundle up logs, save event+options+error, zip “OUT”, and upload to “failed” bucket.
        L.append("EXCEPTION CAUGHT: " + str(e))
        # Prepare an “error” directory under /tmp so we can capture event / options / error.txt / info.json
        ErrBase = pn.createRandomTemporaryPathableFromFileName("a.json")
        ErrBase.appendPath("ERROR_DIR")
        ErrBase.ensureDirectoryExistence()

        # 1) Write event.json
        E_event = ErrBase.duplicate()  # a copy of the ERROR_DIR path
        E_event.changeFileName("event")
        E_event.changeExtension("json")
        try:
            E_event.writeJson(event)
            L.append(f"wrote event → {E_event.getPosition()}")
        except:
            print(f"couldn't write event JSON at {E_event.getPosition()}")

        # 2) Write options.json (the original J)
        E_opts = ErrBase.duplicate()
        E_opts.changeFileName("options")
        E_opts.changeExtension("json")
        try:
            E_opts.writeJson(J)
            L.append(f"wrote options → {E_opts.getPosition()}")
        except:
            print(f"couldn't write options JSON at {E_opts.getPosition()}")

        # 3) Write error.txt
        E_txt = ErrBase.duplicate()
        E_txt.changeFileName("error")
        E_txt.changeExtension("txt")
        with open(E_txt.getPosition(), "w") as f:
            f.write(str(e))
        L.append(f"wrote error.txt → {E_txt.getPosition()}")

        # 4) Write an info.json that includes token/pipelineid and full pn.Log
        INFO = {
            "headers": {
                "options": {
                    "token": token,
                    "pipelineid": pipelineid
                },
                "log": L.log
            }
        }
        E_info = ErrBase.duplicate()
        E_info.changeFileName("info")
        E_info.changeExtension("json")
        try:
            E_info.writeJson(INFO)
            L.append(f"wrote info → {E_info.getPosition()}")
        except:
            # If pn.Pathable.writeJson fails, fallback to sanitizer
            write_json_file(E_info.getPosition(), INFO)
            L.append(f"wrote info via sanitizer → {E_info.getPosition()}")

        # 5) Bundle up everything under ERROR_DIR into a zip
        Zfail = pn.createRandomTemporaryPathableFromFileName("a.zip")
        Zfail.ensureDirectoryExistence()
        base_fail = Zfail.getPosition()[:-4]
        shutil.make_archive(base_fail, "zip", ErrBase.getPath())
        zip_fail_path = Zfail.getPosition()
        L.append(f"zipped failure bundle to {zip_fail_path}")

        # 6) Upload to the “failed” bucket
        try:
            s3.Bucket(mroptimum_failed).upload_file(zip_fail_path, Zfail.getBaseName())
            L.append(f"uploaded failed bundle → s3://{mroptimum_failed}/{Zfail.getBaseName()}")
        except Exception as upload_err:
            print(f"Failed to upload to failed bucket: {upload_err}")

        # 7) Return 500-like response
        return {
            "statusCode": 500,
            "body": json.dumps({"error": str(e)})
        }

def handler(event, context, s3=None):
    """
    AWS Lambda entry point. Calls `do_process(...)` and returns its dict directly.
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    return do_process(event, context,s3=s3)

def main():
    """
    Fargate/Step Functions entry point.  
    Expects the raw S3-trigger JSON to be passed in via the FILE_EVENT environment variable.
    Exits with code 0 on success, or 1 on failure.
    """
    event_str = os.environ.get("FILE_EVENT")
    if not event_str:
        print("No FILE_EVENT provided. Exiting.")
        sys.exit(1)

    try:
        event = json.loads(event_str)
    except Exception as e:
        print(f"Invalid JSON in FILE_EVENT: {e}")
        sys.exit(1)

    result = do_process(event, context=None)
    status = result.get("statusCode", 500)
    if status != 200:
        print(f"do_process returned statusCode {status}. Exiting with 1.")
        sys.exit(1)
    else:
        print("do_process succeeded. Exiting with 0.")
        sys.exit(0)

if __name__ == "__main__":
    main()
