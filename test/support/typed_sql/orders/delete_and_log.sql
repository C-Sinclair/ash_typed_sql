with deleted as (
  delete from orders where id = $1 returning id
)
insert into audit_log (message)
select 'deleted order ' || id from deleted
returning id, message
