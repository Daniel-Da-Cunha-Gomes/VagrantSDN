#!/bin/bash

echo "=== DIAGNOSTIC RYU SDN CONTROLLER ==="
echo ""

echo "1. Vérification de l'installation de Ryu..."
python3 -c "import ryu; print('✓ Ryu importé avec succès')" 2>/dev/null || echo "✗ Erreur d'import Ryu"

echo ""
echo "2. Vérification du fichier sdn_controller.py..."
if [ -f "/opt/ryu/apps/sdn_controller.py" ]; then
    echo "✓ Fichier existe"
    echo "Taille: $(wc -l < /opt/ryu/apps/sdn_controller.py) lignes"
else
    echo "✗ Fichier manquant"
fi

echo ""
echo "3. Test de syntaxe Python..."
python3 -m py_compile /opt/ryu/apps/sdn_controller.py 2>/dev/null && echo "✓ Syntaxe correcte" || echo "✗ Erreur de syntaxe"

echo ""
echo "4. Test d'import du module..."
cd /opt/ryu
python3 -c "
import sys
sys.path.insert(0, '/opt/ryu/apps')
try:
    import sdn_controller
    print('✓ Module importé avec succès')
except Exception as e:
    print(f'✗ Erreur d\\'import: {e}')
"

echo ""
echo "5. Vérification des ports..."
netstat -tlnp | grep -E ':(6633|8080)' && echo "⚠️  Ports déjà utilisés" || echo "✓ Ports libres"

echo ""
echo "6. Test manuel de ryu-manager..."
echo "Tentative de démarrage manuel (5 secondes)..."
timeout 5s /usr/local/bin/ryu-manager --ofp-tcp-listen-port 6633 --wsapi-host 0.0.0.0 --wsapi-port 8080 --verbose /opt/ryu/apps/sdn_controller.py 2>&1 || echo "Arrêt du test manuel"

echo ""
echo "7. Logs récents du service..."
journalctl -u ryu --no-pager -n 10

echo ""
echo "8. Vérification des dépendances..."
python3 -c "
modules = ['ryu', 'eventlet', 'webob', 'routes']
for module in modules:
    try:
        __import__(module)
        print(f'✓ {module}')
    except ImportError as e:
        print(f'✗ {module}: {e}')
"

echo ""
echo "=== FIN DU DIAGNOSTIC ==="
