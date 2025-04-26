import React, { useState } from "react";
import "./App.css";

const API_URL = "https://f7wldcxuzb.execute-api.us-east-1.amazonaws.com/prod/pipeline";
const AUTH_TOKEN = "allow-token"; // This should match your Lambda authorizer

function App() {
  const [jobId, setJobId] = useState("");
  const [inputFile, setInputFile] = useState("");
  const [response, setResponse] = useState("");

  const handleSubmit = async (e) => {
    e.preventDefault();

    try {
      const res = await fetch(API_URL, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": AUTH_TOKEN,
        },
        body: JSON.stringify({
          job_id: jobId,
          input_file: inputFile,
        }),
      });

      const data = await res.json();
      setResponse(JSON.stringify(data, null, 2));
    } catch (error) {
      console.error("Failed to fetch", error);
      setResponse("Failed to submit job. See console for details.");
    }
  };

  return (
    <div className="App">
      <h2>Submit a Job</h2>
      <form onSubmit={handleSubmit}>
        <div>
          <label>Job ID: </label>
          <input
            type="text"
            value={jobId}
            onChange={(e) => setJobId(e.target.value)}
            required
          />
        </div>
        <div>
          <label>Input File (S3 URL): </label>
          <input
            type="text"
            value={inputFile}
            onChange={(e) => setInputFile(e.target.value)}
            required
          />
        </div>
        <button type="submit">Submit Job</button>
      </form>

      {response && (
        <div>
          <h3>Response:</h3>
          <pre>{response}</pre>
        </div>
      )}
    </div>
  );
}

export default App;
