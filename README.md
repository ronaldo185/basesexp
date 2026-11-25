# Versión Flask
Windows (PowerShell):
  python -m venv venv ; .\venv\Scripts\Activate.ps1
  pip install -r requirements.txt
  $env:DATABASE_URL="postgresql://postgres:TU_CLAVE@localhost:5432/gestion_expedientes"
  python app.py     -> http://localhost:3000
Render: Blueprint con render.yaml; define ADMIN_PASS.
