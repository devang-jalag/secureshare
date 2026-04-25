import { useState, useEffect } from 'react';
import { Amplify } from 'aws-amplify';
import { signUp, confirmSignUp, signIn, signOut, fetchAuthSession, getCurrentUser } from 'aws-amplify/auth';
import axios from 'axios';
import './App.css';

Amplify.configure({
  Auth: {
    Cognito: {
      userPoolId: import.meta.env.VITE_USER_POOL_ID,
      userPoolClientId: import.meta.env.VITE_USER_POOL_CLIENT_ID,
    }
  }
});

const API_BASE = import.meta.env.VITE_API_BASE_URL;

function App() {
  const [uiState, setUiState] = useState('signIn');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [error, setError] = useState('');

  const [files, setFiles] = useState([]);
  const [selectedFile, setSelectedFile] = useState(null);
  const [uploadStatus, setUploadStatus] = useState('');
  const [successMessage, setSuccessMessage] = useState('');

  useEffect(() => {
    checkSession();
  }, []);

  const checkSession = async () => {
    try {
      await getCurrentUser();
      setUiState('signedIn');
      fetchFiles();
    } catch {
      // No active session, remain on login view
    }
  };

  // forceRefresh ensures Amplify exchanges the refresh token for a new idToken
  // rather than returning a locally cached, potentially expired token.
  const getToken = async () => {
    const session = await fetchAuthSession({ forceRefresh: true });
    return session.tokens.idToken.toString();
  };

  const fetchFiles = async () => {
    try {
      const token = await getToken();
      const res = await axios.get(`${API_BASE}/files`, {
        headers: { Authorization: `Bearer ${token}` }
      });
      setFiles(res.data.files || []);
      setError('');
    } catch (err) {
      console.error('Failed to fetch file list:', err);
      setError('Unable to retrieve files. Please try again.');
    }
  };

  const handleFileUpload = async (e) => {
    e.preventDefault();
    if (!selectedFile) return;

    setUploadStatus('Uploading...');
    setError('');

    try {
      const token = await getToken();

      const apiResponse = await axios.post(
        `${API_BASE}/generate-url`,
        { filename: selectedFile.name },
        { headers: { Authorization: `Bearer ${token}` } }
      );

      const { presigned_url } = apiResponse.data;

      await axios.put(presigned_url, selectedFile, {
        headers: { 'Content-Type': 'application/octet-stream' }
      });

      setUploadStatus('');
      setSelectedFile(null);
      setSuccessMessage('File uploaded successfully.');
      setTimeout(() => setSuccessMessage(''), 5000);
      document.getElementById('fileInput').value = '';
      fetchFiles();
    } catch (err) {
      console.error('Upload failed:', err);
      setUploadStatus('');
      setError('Upload failed: ' + (err.response?.data?.error || err.message));
    }
  };

  const handleShare = async (file_id) => {
    try {
      const res = await axios.post(`${API_BASE}/download-url`, { file_id });
      const downloadLink = res.data.download_url;
      
      if (navigator.clipboard && window.isSecureContext) {
        await navigator.clipboard.writeText(downloadLink);
        alert('Download link copied to clipboard. Link expires in 1 hour.');
      } else {
        prompt('Copy your download link below (Expires in 1 hour):', downloadLink);
      }
    } catch (err) {
      alert('Error generating share link: ' + (err.response?.data?.error || err.message));
    }
  };

  const handleSignOut = async () => {
    await signOut();
    setUiState('signIn');
    setFiles([]);
  };

  const renderAuthForms = () => (
    <div className="login-container">
      <h1>SecureShare</h1>
      {error && <p style={{ color: '#ff4b4b', fontSize: '14px', textAlign: 'center' }}>{error}</p>}

      {uiState === 'signIn' && (
        <form onSubmit={async (e) => {
          e.preventDefault();
          try {
            await signIn({ username: email, password });
            setUiState('signedIn');
            fetchFiles();
          } catch (err) {
            setError(err.message);
          }
        }}>
          <input className="login-input" type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} required />
          <input className="login-input" type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} required />
          <button type="submit" className="btn-primary">Sign In</button>
          <div className="link-text" onClick={() => setUiState('signUp')}>Create an account</div>
        </form>
      )}

      {uiState === 'signUp' && (
        <form onSubmit={async (e) => {
          e.preventDefault();
          try {
            await signUp({ username: email, password, options: { userAttributes: { email } } });
            setUiState('confirm');
          } catch (err) {
            setError(err.message);
          }
        }}>
          <input className="login-input" type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} required />
          <input className="login-input" type="password" placeholder="Password" value={password} onChange={e => setPassword(e.target.value)} required />
          <button type="submit" className="btn-primary">Create Account</button>
          <div className="link-text" onClick={() => setUiState('signIn')}>Back to sign in</div>
        </form>
      )}

      {uiState === 'confirm' && (
        <form onSubmit={async (e) => {
          e.preventDefault();
          try {
            await confirmSignUp({ username: email, confirmationCode: code });
            setUiState('signIn');
          } catch (err) {
            setError(err.message);
          }
        }}>
          <input className="login-input" type="text" placeholder="Verification code" value={code} onChange={e => setCode(e.target.value)} required />
          <button type="submit" className="btn-primary">Verify Email</button>
        </form>
      )}
    </div>
  );

  return (
    <div>
      {uiState !== 'signedIn' ? renderAuthForms() : (
        <div>
          <div className="header">
            <h1>SecureShare</h1>
            <button className="btn-logout" onClick={handleSignOut}>Sign Out</button>
          </div>

          <div className="container">
            <div className="upload-card">
              <h2>Upload a File</h2>
              <form onSubmit={handleFileUpload}>
                <input
                  id="fileInput"
                  type="file"
                  className="file-input"
                  onChange={(e) => setSelectedFile(e.target.files[0])}
                  required
                />
                <button type="submit" className="btn-upload" disabled={!!uploadStatus}>
                  {uploadStatus || 'Upload'}
                </button>
              </form>
              {error && <p style={{ color: '#ff4b4b', marginTop: '15px' }}>{error}</p>}
              {successMessage && (
                <div style={{ background: '#d4edda', color: '#155724', padding: '12px', borderRadius: '4px', marginTop: '15px', border: '1px solid #c3e6cb' }}>
                  {successMessage}
                </div>
              )}
            </div>

            <h3 style={{ color: '#fff', borderBottom: '1px solid #444', paddingBottom: '10px', fontSize: '20px' }}>
              Active Files
            </h3>

            <div className="file-list">
              {files.length === 0
                ? <p style={{ color: '#888' }}>No active files. Uploaded files are automatically removed after 24 hours.</p>
                : null
              }
              {files.map(f => (
                <div key={f.file_id} className="file-item">
                  <div className="file-header">{f.original_filename}</div>
                  <div className="file-meta">
                    Uploaded: {new Date(f.uploaded_at * 1000).toLocaleString()}
                    &nbsp;&bull;&nbsp;
                    Expires: {new Date(f.expires_at * 1000).toLocaleString()}
                  </div>
                  <button className="btn-share" onClick={() => handleShare(f.file_id)}>
                    Copy Share Link
                  </button>
                </div>
              ))}
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

export default App;
