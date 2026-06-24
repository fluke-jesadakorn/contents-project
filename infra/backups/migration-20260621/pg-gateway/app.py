from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import psycopg2
import os

app = FastAPI()

class Query(BaseModel):
    query: str
    params: list = []

def get_conn():
    return psycopg2.connect(
        host=os.environ.get('PG_HOST', 'postgres'),
        port=int(os.environ.get('PG_PORT', '5432')),
        database=os.environ.get('PG_DATABASE', 'contracts'),
        user=os.environ.get('PG_USER', 'contract'),
        password=os.environ.get('PG_PASSWORD', 'contractpw'),
    )

@app.get('/health')
def health():
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute('SELECT 1')
            return {'ok': True}
    except Exception as e:
        raise HTTPException(500, str(e))

@app.post('/query')
def query(q: Query):
    try:
        with get_conn() as conn, conn.cursor() as cur:
            cur.execute(q.query, q.params)
            if cur.description:
                cols = [c[0] for c in cur.description]
                rows = cur.fetchall()
                return {'rows': [dict(zip(cols, r)) for r in rows]}
            conn.commit()
            return {'affected': cur.rowcount}
    except Exception as e:
        raise HTTPException(500, str(e))
