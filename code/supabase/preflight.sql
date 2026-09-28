-- read-only inventory; contains structure only, no patient rows or secrets
select table_schema, table_name, column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' order by table_name, ordinal_position;
select schemaname, tablename, policyname, roles, cmd, qual, with_check
from pg_policies where schemaname = 'public' order by tablename, policyname;
select n.nspname as schema_name, c.relname as table_name, c.relrowsecurity
from pg_class c join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public' and c.relkind = 'r';
select trigger_schema, event_object_schema, event_object_table, trigger_name, action_statement
from information_schema.triggers where event_object_schema in ('auth','public');
select routine_schema, routine_name, security_type
from information_schema.routines where routine_schema = 'public';
select grantee, table_name, privilege_type from information_schema.role_table_grants
where table_schema = 'public' order by table_name, grantee;
