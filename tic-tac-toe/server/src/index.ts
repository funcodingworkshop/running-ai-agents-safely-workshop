import express, { Request, Response } from 'express';
import { getMessage } from './message.js';

const app = express();
const PORT = process.env.PORT || 5000;

app.use(express.json());

// Sample API route
app.get('/api/message', (req: Request, res: Response) => {
  res.json({ text: getMessage() });
});

app.listen(PORT, () => {
  console.log(`Server running safely on http://localhost:${PORT}`);
});
