const { Client } = require('pg');
const axios = require('axios');

const dbConfig = {
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  user: process.env.DB_USER || 'contract',
  password: process.env.DB_PASSWORD || 'contractpw',
  database: process.env.DB_NAME || 'finance_db',
};

const OLLAMA_URL = process.env.OLLAMA_URL || 'http://localhost:11434';
const EMBED_MODEL = process.env.EMBED_MODEL || 'bge-m3:latest';

// Test descriptions (some in Thai, some in English, some mixed)
const testQueries = [
  'ค่าแท็กซี่ไปพบลูกค้าที่สาทร',
  'ซื้อกระดาษ A4 และซองจดหมาย',
  'เลี้ยงกาแฟลูกค้าตอนประชุม',
  'ค่าเน็ตออฟฟิศรอบเดือนพฤษภา',
  'Renew AWS cloud hosting subscription',
  'ซ่อมแอร์ห้องประชุมใหญ่',
  'ค่าส่งของด่วนผ่าน Lalamove'
];

async function run() {
  const client = new Client(dbConfig);
  try {
    await client.connect();
    console.log('Connected to database for query test.\n');

    for (const query of testQueries) {
      console.log(`Query: "${query}"`);
      
      // 1. Get embedding from Ollama
      const ollamaRes = await axios.post(`${OLLAMA_URL}/api/embed`, {
        model: EMBED_MODEL,
        input: query
      });

      const embedding = ollamaRes.data.embeddings 
        ? ollamaRes.data.embeddings[0] 
        : ollamaRes.data.embedding;

      if (!embedding) {
        console.error(`Failed to get embedding for: ${query}`);
        continue;
      }

      const vectorStr = `[${embedding.join(',')}]`;

      // 2. Perform Cosine Similarity Query in Postgres
      // pgvector <=> operator computes Cosine Distance (1 - Cosine Similarity)
      // So smaller distance means higher similarity.
      const queryStr = `
        SELECT code, name, name_th, 
               (1 - (embedding <=> $1::vector)) as similarity
        FROM chart_of_accounts
        ORDER BY similarity DESC
        LIMIT 3;
      `;

      const res = await client.query(queryStr, [vectorStr]);
      
      // Print results
      res.rows.forEach((row, idx) => {
        const percentage = (row.similarity * 100).toFixed(2);
        console.log(`  ${idx + 1}. [${row.code}] ${row.name} (${row.name_th}) - Score: ${percentage}%`);
      });
      console.log();
    }
  } catch (err) {
    console.error('Error during semantic mapping test:', err);
  } finally {
    await client.end();
  }
}

run();
