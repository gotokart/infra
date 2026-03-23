#!/bin/bash
echo "Rolling back backend on Railway..."
railway rollback --service gotokart-backend
echo "Rollback complete!"
