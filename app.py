import os, re, json
import psycopg2, psycopg2.extras, psycopg2.extensions as ext
from flask import Flask, request, jsonify, send_from_directory, Response
from werkzeug.exceptions import HTTPException

# fechas como texto (evita problemas de zona horaria al serializar)
ext.register_type(ext.new_type(ext.DATE.values, 'DATE_STR', lambda v, c: v))
ext.register_type(ext.new_type(ext.PYDATETIME.values, 'TS_STR', lambda v, c: v))

BASE = os.path.dirname(os.path.abspath(__file__))
URL = os.environ.get('DATABASE_URL', 'postgresql://postgres:postgres@localhost:5432/gestion_expedientes')
app = Flask(__name__, static_folder=None)
META = {}

def run(sql, params=None):
    c = psycopg2.connect(URL, sslmode='disable' if re.search(r'localhost|127\.0\.0\.1', URL) else 'require')
    c.autocommit = True
    try:
        with c.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
            cur.execute(sql, params)
            return (cur.fetchall(), [d.name for d in cur.description]) if cur.description else ([], [])
    finally:
        c.close()
R = lambda sql, p=None: run(sql, p)[0]

def load_meta():
    cols = R("""select table_name t, column_name n, data_type ty, character_maximum_length len, is_nullable='YES' as nullable,
        column_default as def, is_identity='YES' as identity from information_schema.columns
        where table_schema='public' order by table_name, ordinal_position""")
    keys = R("""select tc.table_name t, kcu.column_name n, tc.constraint_type ct, ccu.table_name rt, ccu.column_name rc
        from information_schema.table_constraints tc
        join information_schema.key_column_usage kcu on kcu.constraint_name=tc.constraint_name and kcu.table_schema=tc.table_schema
        left join information_schema.constraint_column_usage ccu on ccu.constraint_name=tc.constraint_name and tc.constraint_type='FOREIGN KEY'
        where tc.table_schema='public' and tc.constraint_type in ('PRIMARY KEY','FOREIGN KEY','UNIQUE')""")
    META.clear()
    for r in cols:
        ty = f"varchar({r['len']})" if r['ty'] == 'character varying' else r['ty'].replace('timestamp without time zone', 'timestamp')
        META.setdefault(r['t'], []).append(dict(name=r['n'], type=ty, nullable=r['nullable'], **{'def': r['def']}, identity=r['identity'], pk=False, unique=False, fk=None))
    for k in keys:
        col = next((x for x in META.get(k['t'], []) if x['name'] == k['n']), None)
        if not col: continue
        if k['ct'] == 'PRIMARY KEY': col['pk'] = True
        elif k['ct'] == 'UNIQUE': col['unique'] = True
        else: col['fk'] = {'table': k['rt'], 'col': k['rc']}

def init():
    if not R("select to_regclass('public.expediente') as t")[0]['t']:
        c = psycopg2.connect(URL, sslmode='disable' if re.search(r'localhost|127\.0\.0\.1', URL) else 'require')
        c.autocommit = True
        c.cursor().execute(open(os.path.join(BASE, 'schema.sql'), encoding='utf-8').read())
        c.close(); print('Esquema creado')
    load_meta()

FR = {'23503': 'No se puede completar: hay registros relacionados (o la referencia no existe).',
      '23505': 'Ya existe un registro con ese valor único.', '23502': 'Falta un campo obligatorio.',
      '23514': 'Los datos no cumplen una regla de validación (revisa las fechas).',
      '22P02': 'Formato de dato no válido.', '22007': 'Fecha no válida.'}

@app.errorhandler(Exception)
def on_error(e):
    if isinstance(e, HTTPException): return e
    return jsonify(error=FR.get(getattr(e, 'pgcode', None)) or str(e).strip()), 400

@app.before_request
def auth():
    pw = os.environ.get('ADMIN_PASS')
    if not pw: return
    a = request.authorization
    if a and a.username == os.environ.get('ADMIN_USER', 'admin') and a.password == pw: return
    return Response(status=401, headers={'WWW-Authenticate': 'Basic realm="Expedientes"'})

def tbl(t):
    if t not in META: raise ValueError('Tabla no válida')
    return META[t]
pks = lambda m: [c['name'] for c in m if c['pk']]

@app.get('/')
def index(): return send_from_directory(os.path.join(BASE, 'public'), 'index.html')

@app.get('/api/meta')
def meta(): return jsonify(META)

@app.get('/api/lookup/<t>')
def lookup(t):
    m = tbl(t); names = {c['name'] for c in m}
    lbl = "nombres||' '||apellidos" if 'nombres' in names else "codigo||' - '||titulo" if 'codigo' in names else 'nombre' if 'nombre' in names else 'titulo'
    return jsonify(R(f'select {pks(m)[0]} id, {lbl} label from "{t}" order by 2'))

@app.get('/api/t/<t>')
def listar(t):
    tbl(t); term = request.args.get('q', '').strip()
    if term: return jsonify(R(f'select * from "{t}" where "{t}"::text ilike %s order by 1 desc limit 500', (f'%{term}%',)))
    return jsonify(R(f'select * from "{t}" order by 1 desc limit 500'))

@app.post('/api/t/<t>')
def crear(t):
    m = tbl(t); b = request.get_json()
    cols = [c['name'] for c in m if not c['identity'] and c['name'] in b]
    if cols:
        sql = f'insert into "{t}" ({",".join(chr(34)+c+chr(34) for c in cols)}) values ({",".join(["%s"]*len(cols))}) returning *'
    else:
        sql = f'insert into "{t}" default values returning *'
    return jsonify(R(sql, [b[c] for c in cols])[0])

@app.put('/api/t/<t>')
def editar(t):
    m = tbl(t); b = request.get_json(); pk, data = b['pk'], b['data']; ks = pks(m)
    cols = [c['name'] for c in m if not c['pk'] and not c['identity'] and c['name'] in data]
    if not cols: return jsonify(ok=True)
    sql = f'update "{t}" set {",".join(f"{chr(34)}{c}{chr(34)}=%s" for c in cols)} where {" and ".join(f"{chr(34)}{k}{chr(34)}=%s" for k in ks)} returning *'
    return jsonify(R(sql, [data[c] for c in cols] + [pk[k] for k in ks])[0])

@app.delete('/api/t/<t>')
def eliminar(t):
    m = tbl(t); pk = json.loads(request.args['pk']); ks = pks(m)
    run(f'delete from "{t}" where {" and ".join(f"{chr(34)}{k}{chr(34)}=%s" for k in ks)}', [pk[k] for k in ks])
    return jsonify(ok=True)

@app.get('/api/stats')
def stats():
    k = R("""select (select count(*) from expediente)::int expedientes,
      (select count(*) from expediente e join estado s using(id_estado) where not s.es_final)::int abiertos,
      (select count(*) from funcionario where activo)::int funcionarios, (select count(*) from persona)::int personas,
      (select count(*) from documento)::int documentos, (select count(*) from actuacion)::int actuaciones,
      (select count(*) from expediente e join estado s using(id_estado) where not s.es_final and not exists(select 1 from asignacion a where a.id_expediente=e.id_expediente and a.es_responsable and a.fecha_fin is null))::int sin_responsable,
      (select count(*) from expediente e join estado s using(id_estado) where not s.es_final and e.fecha_apertura < current_date-30)::int antiguos,
      (select round(avg(fecha_cierre-fecha_apertura),1)::float from expediente where fecha_cierre is not null) prom_cierre""")[0]
    estado = R("select s.nombre label, count(e.id_expediente)::int n from estado s left join expediente e using(id_estado) group by s.id_estado, s.nombre order by s.id_estado")
    tipo = R("select t.nombre label, count(e.id_expediente)::int n from tipo_caso t left join expediente e using(id_tipo_caso) group by t.id_tipo_caso, t.nombre order by 2 desc")
    mes = R("select to_char(date_trunc('month',fecha_apertura),'YYYY-MM') label, count(*)::int n from expediente group by 1 order by 1 desc limit 12")[::-1]
    act = R("""select e.codigo, a.titulo, to_char(a.fecha_actuacion,'YYYY-MM-DD HH24:MI') fecha, f.nombres||' '||f.apellidos funcionario
       from actuacion a join expediente e using(id_expediente) join funcionario f using(id_funcionario) order by a.fecha_actuacion desc limit 6""")
    carga = R("select f.nombres||' '||f.apellidos label, count(a.id_asignacion)::int n from funcionario f left join asignacion a on a.id_funcionario=f.id_funcionario and a.fecha_fin is null where f.activo group by f.id_funcionario order by 2 desc limit 5")
    alertas = R("select e.codigo, e.titulo, s.nombre estado, (current_date-e.fecha_apertura)::int dias, not exists(select 1 from asignacion a where a.id_expediente=e.id_expediente and a.es_responsable and a.fecha_fin is null) sin_responsable from expediente e join estado s using(id_estado) where not s.es_final and (not exists(select 1 from asignacion a where a.id_expediente=e.id_expediente and a.es_responsable and a.fecha_fin is null) or e.fecha_apertura < current_date-30) order by dias desc limit 8")
    return jsonify(k=k, estado=estado, tipo=tipo, mes=mes, act=act, carga=carga, alertas=alertas)

RESP = "(select f.nombres||' '||f.apellidos from asignacion a join funcionario f using(id_funcionario) where a.id_expediente=e.id_expediente and a.es_responsable and a.fecha_fin is null)"
DATES = "(%(d)s::date is null or e.fecha_apertura>=%(d)s::date) and (%(h)s::date is null or e.fecha_apertura<=%(h)s::date)"
REPORTS = {
 'expedientes': ('Expedientes (detalle)', True, f"select e.codigo, e.titulo, tc.nombre tipo, s.nombre estado, e.fecha_apertura, e.fecha_cierre, {RESP} responsable from expediente e join tipo_caso tc using(id_tipo_caso) join estado s using(id_estado) where {DATES} order by e.fecha_apertura desc"),
 'por_estado': ('Expedientes por estado', True, f"select s.nombre estado, count(e.id_expediente)::int total from estado s left join expediente e on e.id_estado=s.id_estado and {DATES} group by s.id_estado, s.nombre order by s.id_estado"),
 'por_tipo': ('Expedientes por tipo de caso', True, f"select t.nombre tipo, count(e.id_expediente)::int total from tipo_caso t left join expediente e on e.id_tipo_caso=t.id_tipo_caso and {DATES} group by t.nombre order by 2 desc"),
 'carga': ('Carga de trabajo por funcionario', False, "select f.nombres||' '||f.apellidos funcionario, f.cargo, count(a.id_asignacion)::int asignaciones_activas from funcionario f left join asignacion a on a.id_funcionario=f.id_funcionario and a.fecha_fin is null where f.activo group by f.id_funcionario order by 3 desc"),
 'sin_responsable': ('Expedientes abiertos sin responsable', False, f"select e.codigo, e.titulo, s.nombre estado, e.fecha_apertura from expediente e join estado s using(id_estado) where not s.es_final and {RESP} is null order by e.fecha_apertura"),
 'actuaciones': ('Últimas 100 actuaciones', False, "select e.codigo, a.titulo, a.fecha_actuacion, f.nombres||' '||f.apellidos funcionario from actuacion a join expediente e using(id_expediente) join funcionario f using(id_funcionario) order by a.fecha_actuacion desc limit 100"),
 'documentos': ('Documentos por expediente', False, "select e.codigo, td.nombre tipo, d.nombre documento, d.fecha_documento, d.ubicacion_archivo from documento d join expediente e using(id_expediente) join tipo_documento td using(id_tipo_documento) order by e.codigo, d.fecha_documento"),
}

@app.get('/api/reports')
def reports(): return jsonify([dict(key=k, t=v[0], f=v[1]) for k, v in REPORTS.items()])

@app.get('/api/report/<key>')
def report(key):
    if key not in REPORTS: raise ValueError('Reporte no válido')
    _, f, sql = REPORTS[key]
    rows, cols = run(sql, {'d': request.args.get('desde') or None, 'h': request.args.get('hasta') or None} if f else None)
    return jsonify(cols=cols, rows=rows)

init()
if __name__ == '__main__':
    app.run(port=int(os.environ.get('PORT', 3000)), debug=False)
