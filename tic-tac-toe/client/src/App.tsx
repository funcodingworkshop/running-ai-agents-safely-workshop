import { useEffect, useState } from 'react';

function App() {
  const [message, setMessage] = useState<string>('Loading...');

  useEffect(() => {
    fetch('/api/message')
      .then((res) => res.json())
      .then((data) => setMessage(data.text))
      .catch(() => setMessage('Failed to connect to server.'));
  }, []);

  return (
    <div style={{ textAlign: 'center', marginTop: '50px' }}>
      <h1>Client-Server Boilerplate</h1>
      <p>Backend response: <strong>{message}</strong></p>
    </div>
  );
}

export default App;
