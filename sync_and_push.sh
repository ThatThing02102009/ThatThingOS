#!/bin/bash
git add .
git commit -m "Build Fix: Docker extraction & Kernel sync - $(date +'%Y-%m-%d')" || true
git pull --rebase origin main
git push origin main
