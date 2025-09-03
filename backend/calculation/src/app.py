#!/usr/bin/env python3
import json
import traceback
import boto3
import os
import shutil
import sys
from pathlib import Path
import tempfile
import uuid

from pynico_eros_montin import pynico as pn


class PrintingLogger(pn.Log):
    def write(self, message, type=None, settings=None):
        print(message)
        return super().append(str(message), type, settings)


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
        with open(file_path, "w", encoding="utf-8") as f:
            json.dump(sanitized_data, f, indent=4)
        print(f"JSON data successfully written to {file_path}")
    except Exception as e:
        print(f"Failed to write JSON data to file: {e}")


def pick_random_path(suffix):
    """Create a random temporary file path."""
    temp_dir = Path(tempfile.gettempdir())
    random_name = f"{uuid.uuid4().hex}{suffix}"
    return temp_dir / random_name


def create_random_temp_dir():
    directory = pick_random_path("")
    directory.mkdir()
    return directory


def download_from_s3(file_info, s3=None, pt="/tmp"):
    """
    If file_info == {"bucket": ..., "key": ..., "filename": ...}, download that S3 object
    into a random file under `pt`, then set file_info["filename"] to the local path and
    file_info["type"] = "local".
    """
    key = file_info["key"]
    bucket = file_info["bucket"]
    filename = file_info["filename"]
    if s3 is None:
        s3 = boto3.resource("s3")

    # Create random local path
    local_path = pick_random_path(suffix=Path(filename).suffix)

    s3.Bucket(bucket).download_file(key, str(local_path))
    file_info["filename"] = str(local_path)
    file_info["type"] = "local"


def do_process(event, context=None, s3=None):
    """
    Core logic that:
      1. Creates a pn.Log for tracing.
      2. Downloads the incoming JSON from S3.
      3. Parses pipeline/task/options flags.
      4. Downloads any referenced S3 files (noise/signal) locally.
      5. Runs `python -m mrotools.snr …`.
      6. If successful: zip "OUT" and upload to `ResultsBucketName`.
      7. On error: collect logs, write error files, zip "OUT" and upload to `FailedBucketName`.
      8. Return a dict suitable for AWS Lambda (statusCode/body).
    """
    # Read bucket names from environment (set in Lambda config or Fargate Task Definition)
    result_bucket = os.getenv("ResultsBucketName", "mrorv2")
    failed_bucket = os.getenv("FailedBucketName", "mrofv2")

    # Initialize logging
    logger = PrintingLogger("mroptimum job", {"event": event, "context": context or {}})

    try:
        # Prepare S3 resource
        if s3 is None:
            s3 = boto3.resource("s3")

        # s3 implementation
        if "Records" in event and event["Records"] and "s3" in event["Records"][0]:
            # ----- S3 path: extract bucket/key, download JSON -----
            bucket_name = event["Records"][0]["s3"]["bucket"]["name"]
            file_key = event["Records"][0]["s3"]["object"]["key"]
            logger.write(f"bucket_name {bucket_name}")
            logger.write(f"file_key {file_key}")

            # Download the JSON payload to /tmp/<random>.json
            fj = pick_random_path(suffix=".json")
            s3.Bucket(bucket_name).download_file(file_key, str(fj))
            logger.write(f"file downloaded to {fj}")

            # Read that JSON from local
            with open(fj, "r") as f:
                info_json = json.load(f)
            logger.write("json file read")
        else:
            # no S3 event, assume direct payload
            logger.write("no S3 event, using direct payload")
            info_json = event
            logger.write("using direct payload from API")
            # If you want to preserve the "alias" or "pipeline" in logs:
            if "alias" in info_json:
                logger.write(f"alias {info_json.get('alias')}")
            if "pipeline" in info_json:
                logger.write(f"pipeline {info_json.get('pipeline')}")

        # ───────────────────────────────────────────────
        # 2) Extract pipelineid, token, OUTPUT flags from J
        # ───────────────────────────────────────────────
        pipelineid = info_json.get("pipeline", None)
        token = info_json.get("token", None)
        user_id = info_json.get("user_id", None)
        info_json_output = info_json.get("output", {})
        logger.write(f"pipelineid {pipelineid}")
        logger.write(f"token {token}")

        # Determine flags for coilsensitivity, matlab, gfactor
        savecoils = "--no-coilsens"
        savematlab = "--no-matlab"
        savegfactor = "--no-gfactor"
        if info_json_output.get("coilsensitivity"):
            savecoils = "--coilsens"
        if info_json_output.get("matlab"):
            savematlab = "--matlab"
        if info_json_output.get("gfactor"):
            savegfactor = "--gfactor"
        logger.write(f"savecoils {savecoils}")
        logger.write(f"savematlab {savematlab}")
        logger.write(f"savegfactor {savegfactor}")

        # 5) Get the task dict
        task_info = info_json["task"]
        NOISE_AVAILABLE = False
        SIGNAL_AVAILABLE = False
        MULTIRAID = False
        # 6) If noise or signal == S3 type, download locally
        recon_opts = task_info["options"]["reconstructor"]["options"]
        if "noise" in recon_opts:
            noise_opts = recon_opts["noise"]["options"]
            if noise_opts.get("type") == "s3":
                download_from_s3(noise_opts, s3)
                logger.write("noise file downloaded")
                NOISE_AVAILABLE = True
        else:
            # If "noise" is not present, we skip this step
            logger.write("no noise options found, skipping download")

        if "signal" in recon_opts:
            signal_opts = recon_opts["signal"]["options"]
            if signal_opts.get("type") == "s3":
                download_from_s3(signal_opts, s3)
                logger.write("signal file downloaded")
                SIGNAL_AVAILABLE = True
                if signal_opts.get("vendor", "").lower() == "siemens":
                    # If vendor is mroptimum, we can use the signal options directly
                    logger.write("signal vendor is mroptimum, using options directly")
                    MULTIRAID = signal_opts.get("multiraid", False)
        else:
            # If "signal" is not present, we skip this step
            logger.write("no signal options found, skipping download")

        # 7) Write updated T → /tmp/<random>.json for mrotools.snr
        task_info["token"] = token
        task_info["pipelineid"] = pipelineid

        mrotools_input_json_file = pick_random_path(suffix=".json")
        with open(mrotools_input_json_file, "w") as f:
            json.dump(task_info, f)
        logger.write(f"writeJson for mrotools input: {mrotools_input_json_file}")

        # 8) Prepare output folder under /tmp: /tmp/<random>/OUT
        out_base = create_random_temp_dir()
        out_dir = out_base / "OUT"
        out_dir.mkdir(parents=True)
        logger.write(f"output dir set to {out_dir}")

        # 9) Prepare a logfile path
        log_path = pick_random_path(suffix=".log")

        # 10) Run the mrotools.snr command
        BashItObject = pn.BashIt()
        # In Lambda we do "--no-parallel" because CPU cores are limited;
        # in Fargate you can remove that flag or change to "--parallel" if desired.
        # Here we keep it as "--no-parallel" by default, but you can override via ENV if needed.
        parallel_flag = os.getenv("MROPARALLEL", "false").lower()
        if parallel_flag in ("true", "1", "yes"):
            parallel_arg = "--parallel"
        else:
            parallel_arg = "--no-parallel"

        # check noise and signal availability
        if (NOISE_AVAILABLE or MULTIRAID) and SIGNAL_AVAILABLE:
            logger.write("noise and signal available, proceeding with computation")
        else:
            logger.write("WARNING: noise or signal not available, using --no-parallel")
            raise Exception(
                "Noise or signal not available, cannot proceed with computation"
            )

        cmd = (
            f"python -m mrotools.snr "
            f"-j {mrotools_input_json_file} "
            f"-o {out_dir} "
            f"{parallel_arg} {savematlab} {savecoils} {savegfactor} "
            f"--no-verbose "
            f"-l {log_path}"
        )
        BashItObject.setCommand(cmd)
        logger.write(f"running command: {cmd}")
        BashItObject.run()

        # 11) Inspect the generated log for errors
        g = pn.Log()
        g.appendFullLog(str(log_path))
        if g.log and g.log[-1].get("what") == "ERROR":
            # If the final log entry says "ERROR", treat as a computation failure
            logger.write("ERROR in the computation")
            logger.appendFullLog(str(log_path))
            raise Exception("ERROR in the computation")

        logger.write("computation completed successfully")
        logger.appendFullLog(str(log_path))

        try:
            print("Fixing up info.json")
            info_json_path = out_dir / "info.json"
            with open(info_json_path, "r") as f:
                info_json_data = json.load(f)
            info_json_data["user_id"] = user_id
            with open(info_json_path, "w") as f:
                json.dump(info_json_data, f)
        except:
            traceback.print_exc()
            print("Failed to fix up info.json")

        # 12) Zip the entire OUT folder
        zip_path = Path(
            shutil.make_archive(pick_random_path(suffix=""), "zip", str(out_dir))
        )

        logger.write(f"zipped output to {zip_path}")

        # 13) Upload zip to the "results" bucket
        key = f"MR Optimum/{user_id}/{zip_path.name}"
        s3.Bucket(result_bucket).upload_file(str(zip_path), key)
        logger.write(f"uploaded results → s3://{result_bucket}/{key}")

        # 14) Return success (Lambda will interpret this as a 200)
        return {
            "statusCode": 200,
            "body": json.dumps({"results": {"key": key, "bucket": result_bucket}}),
        }

    except Exception as error:
        # On *any* exception, bundle up logs, save event+options+error, zip "OUT", and upload to "failed" bucket.
        error_formatted = traceback.format_exc()
        logger.write(error_formatted)
        # logger.write("EXCEPTION CAUGHT: " + str(e))

        # Prepare an "error" directory under /tmp so we can capture event / options / error.txt / info.json
        err_base = create_random_temp_dir()
        error_dir = err_base / "ERROR_DIR"
        error_dir.mkdir(parents=True, exist_ok=True)

        # 1) Write event.json
        event_file = error_dir / "event.json"
        try:
            with open(event_file, "w") as f:
                json.dump(event, f, indent=4)
            logger.write(f"wrote event → {event_file}")
        except:
            traceback.print_exc()
            print(f"couldn't write event JSON at {event_file}")

        # 2) Write options.json (the original J)
        opts_file = error_dir / "options.json"
        try:
            with open(opts_file, "w") as f:
                json.dump(info_json, f, indent=4)
            logger.write(f"wrote options → {opts_file}")
        except:
            traceback.print_exc()
            print(f"couldn't write options JSON at {opts_file}")

        # 3) Write error.txt
        error_file = error_dir / "error.txt"
        with open(error_file, "w") as f:
            f.write(error_formatted)
        logger.write(f"wrote error.txt → {error_file}")

        # 4) Write an info.json that includes token/pipelineid and full pn.Log
        info_json_out = {
            "headers": {
                "options": {"token": token, "pipelineid": pipelineid},
                "log": logger.log,
            },
            "user_id": user_id,
        }
        info_file = error_dir / "info.json"
        try:
            with open(info_file, "w") as f:
                json.dump(info_json_out, f, indent=4)
            logger.write(f"wrote info → {info_file}")
        except:
            # If standard JSON fails, use sanitizer
            write_json_file(str(info_file), info_json_out)
            logger.write(f"wrote info via sanitizer → {info_file}")

        # 5) Bundle up everything under ERROR_DIR into a zip
        zip_fail_path = Path(
            shutil.make_archive(
                pick_random_path(suffix=""),
                "zip",
                str(error_dir),
            )
        )
        logger.write(f"zipped failure bundle to {zip_fail_path}")

        # 6) Upload to the "failed" bucket
        try:
            key = f"MR Optimum/{user_id}/{zip_fail_path.name}"
            s3.Bucket(failed_bucket).upload_file(str(zip_fail_path), key)
            logger.write(f"uploaded failed bundle → s3://{failed_bucket}/{key}")
        except Exception as upload_err:
            traceback.print_exc()
            print(f"Failed to upload to failed bucket: {upload_err}")
            return {
                "statusCode": 500,
                "body": json.dumps(
                    {
                        "error": error_formatted,
                        "s3_error": "\n".join(traceback.format_exc()),
                    }
                ),
            }

        # 7) Return 500-like response
        return {"statusCode": 500, "body": json.dumps({"error": error_formatted})}


def handler(event, context, s3=None):
    """
    AWS Lambda entry point. Calls `do_process(...)` and returns its dict directly.
    """
    print(f"Received event: {json.dumps(event, indent=2)}")
    return do_process(event, context, s3=s3)


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
