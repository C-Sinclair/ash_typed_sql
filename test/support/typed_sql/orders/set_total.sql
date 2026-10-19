update orders set total = $2
where id = $1
returning *
