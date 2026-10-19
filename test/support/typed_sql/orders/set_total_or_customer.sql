update orders set total = $2
where id = $1 or customer_id = $3
returning *
