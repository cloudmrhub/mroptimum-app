// src/components/JobForm.jsx
import React, { useState } from 'react';

const JobForm = () => {
  const [jobId, setJobId] = useState('');
  const [inputFile, setInputFile] = useState('');
  const [message, setMessage] = useState('');

  const handleSubmit = async (e) => {
    e.preventDefault();

    const res = await fetch('https://narhgodst5.execute-api.us-east-1.amazonaws.com/prod/pipeline', {
      method: 'POST',
      headers: {
        'Authorization': 'allow-token',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        job_id: jobId,
        input_file: inputFile,
      }),
    });

    const data = await res.json();
    setMessage(data.message || 'Submitted!');
  };

  return (
    <div style={{ padding: '2rem' }}>
      <h2>Submit a New Job</h2>
      <form onSubmit={handleSubmit}>
        <div>
          <label>Job ID:</label>
          <input value={jobId} onChange={(e) => setJobId(e.target.value)} required />
        </div>
        <div>
          <label>Input File (S3 path):</label>
          <input value={inputFile} onChange={(e) => setInputFile(e.target.value)} required />
        </div>
        <button type="submit">Submit Job</button>
      </form>
      {message && <p>{message}</p>}
    </div>
  );
};

export default JobForm;
