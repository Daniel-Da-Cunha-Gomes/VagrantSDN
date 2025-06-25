#!/bin/bash

# # Aller dans le dossier de l'application Ryu
# cd ..\ryu-controller\ || exit 1

# Lancer Ryu avec ton app
ryu-manager --verbose simple_http_redirect.py
