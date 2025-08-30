const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 81 });

wss.on('connection', (ws) => {
  console.log('Un client WebSocket est connecté');

  ws.on('message', (message) => {
    console.log('Message reçu: %s', message);
    // Renvoie en écho le message reçu
    ws.send(`Echo: ${message}`);
  });

  ws.on('close', () => {
    console.log('Client déconnecté');
  });

  // Message de bienvenue à la connexion
  ws.send('Bienvenue sur le serveur WebSocket!');
});

console.log('Serveur WebSocket démarré et écoute sur le port 81');
