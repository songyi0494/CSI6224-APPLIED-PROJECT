import { createServer } from 'node:http';
import { evaluateAssessment } from '../supabase/functions/evaluate_pathway_1/engine.ts';
// local synthetic-data service; never deploy this unauthenticated demo endpoint
createServer(async (req,res)=>{
  res.setHeader('Access-Control-Allow-Origin','*');
  res.setHeader('Access-Control-Allow-Headers','content-type');
  res.setHeader('Access-Control-Allow-Methods','POST, OPTIONS');
  res.setHeader('Content-Type','application/json');
  if(req.method==='OPTIONS'){res.writeHead(204);res.end();return;}
  if(req.url!='/evaluate'||req.method!=='POST'){res.writeHead(404);res.end('{}');return;}
  try {
    let body='';for await(const chunk of req){body+=chunk;if(body.length>50000)throw new Error('Input too large');}
    const {facts}=JSON.parse(body);if(!facts||Array.isArray(facts)||typeof facts!=='object')throw new Error('Invalid facts');
    res.end(JSON.stringify(evaluateAssessment(facts)));
  }catch{res.writeHead(400);res.end(JSON.stringify({error:'Invalid assessment'}));}
}).listen(8787,'127.0.0.1',()=>console.log('Synthetic-data rule service: http://localhost:8787/evaluate'));
