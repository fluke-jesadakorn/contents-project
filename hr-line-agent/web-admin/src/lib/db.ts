import { Pool } from 'pg';

const pool = new Pool({
  user: process.env.POSTGRES_USER || 'contract',
  password: process.env.POSTGRES_PASSWORD || 'contractpw',
  host: process.env.POSTGRES_HOST || 'localhost',
  database: process.env.POSTGRES_DB || 'hr_db',
  port: parseInt(process.env.POSTGRES_PORT || '5432'),
});

export const query = (text: string, params?: any[]) => pool.query(text, params);
export default pool;
