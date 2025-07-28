const express = require('express');
const os = require('os');
const app = express();
const PORT = process.env.PORT || 3000;

// Get deployment color from environment (blue/green)
const APP_COLOR = process.env.APP_COLOR || 'blue';

app.get('/', (req, res) => {
  res.send(`
    <html>
      <body style="background-color: ${APP_COLOR === 'blue' ? '#3498db' : '#2ecc71'};">
        <div style="text-align: center; padding: 100px; color: white;">
          <h1>Welcome to CapGemini EKS Deployment</h1>
          <h2>Running on: ${os.hostname()}</h2>
          <h3>Version: ${APP_COLOR.toUpperCase()}</h3>
          <p>${new Date().toISOString()}</p>
        </div>
      </body>
    </html>
  `);
});

app.get('/health', (req, res) => {
  res.status(200).json({
    status: 'OK',
    version: APP_COLOR,
    host: os.hostname(),
    timestamp: new Date().toISOString()
  });
});

app.listen(PORT, () => {
  console.log(`Server running on port ${PORT} (${APP_COLOR} version)`);
});
