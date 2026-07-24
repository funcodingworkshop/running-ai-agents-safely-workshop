"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const message_js_1 = require("./message.js");
const app = (0, express_1.default)();
const PORT = process.env.PORT || 5000;
app.use(express_1.default.json());
// Sample API route
app.get('/api/message', (req, res) => {
    res.json({ text: (0, message_js_1.getMessage)() });
});
app.listen(PORT, () => {
    console.log(`Server running safely on http://localhost:${PORT}`);
});
