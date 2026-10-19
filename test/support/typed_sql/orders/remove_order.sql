delete from orders
where id = $1
returning *
