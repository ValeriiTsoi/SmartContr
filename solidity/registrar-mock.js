const express = require('express'); const app = express();
app.use(express.json());
app.post('/register', (req, res) => res.json({ externalRegIdHex: '0x' + '11'.repeat(32) }));
app.listen(3000, () => console.log('Registrar mock on http://0.0.0.0:3000'));
