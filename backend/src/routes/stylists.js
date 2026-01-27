const express = require('express');
const router = express.Router();

router.get('/', async (req, res) => {
  res.json({ success: true, data: [] });
});

router.get('/:id', async (req, res) => {
  res.json({ success: true, data: {} });
});

router.post('/', async (req, res) => {
  res.status(201).json({ success: true, message: 'Stylist created' });
});

router.put('/:id', async (req, res) => {
  res.json({ success: true, message: 'Stylist updated' });
});

router.delete('/:id', async (req, res) => {
  res.json({ success: true, message: 'Stylist deleted' });
});

router.get('/:id/availability', async (req, res) => {
  res.json({ success: true, data: { available: [] } });
});

module.exports = router;
