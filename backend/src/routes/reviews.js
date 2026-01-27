const express = require('express');
const router = express.Router();

router.get('/', async (req, res) => {
  res.json({ success: true, data: [] });
});

router.get('/stylist/:stylistId', async (req, res) => {
  res.json({ success: true, data: [] });
});

router.post('/', async (req, res) => {
  res.status(201).json({ success: true, message: 'Review created' });
});

router.put('/:id', async (req, res) => {
  res.json({ success: true, message: 'Review updated' });
});

router.delete('/:id', async (req, res) => {
  res.json({ success: true, message: 'Review deleted' });
});

module.exports = router;
