import pg from 'pg';

const num = (v: string | undefined, d: number) => (v ? parseInt(v, 10) : d);

export const dbConfig = {
  user: process.env.POSTGRES_USER || 'contract',
  password: process.env.POSTGRES_PASSWORD || 'contractpw',
  host: process.env.POSTGRES_HOST || 'localhost',
  database: process.env.POSTGRES_DB || 'finance_db',
  port: num(process.env.POSTGRES_PORT, 5432),
};

export const pool = new pg.Pool({
  ...dbConfig,
  max: 20,
  idleTimeoutMillis: 30_000,
});

export const query = <T extends pg.QueryResultRow = pg.QueryResultRow>(
  text: string,
  params?: unknown[],
) => pool.query<T>(text, params as never);