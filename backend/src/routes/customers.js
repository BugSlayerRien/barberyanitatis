const express = require('express');
const router = express.Router();

router.get('/', async (req, res) => {
  res.json({ success: true, data: [] });
});

router.get('/:id', async (req, res) => {
  res.json({ success: true, data: {} });
});

router.put('/:id', async (req, res) => {
  res.json({ success: true, message: 'Customer updated' });
});

router.delete('/:id', async (req, res) => {
  res.json({ success: true, message: 'Customer deleted' });
});

module.exports = router;
