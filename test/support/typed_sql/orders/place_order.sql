insert into orders (customer_id, total)
values ($1, $2)
returning *
