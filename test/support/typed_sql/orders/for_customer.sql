select * from orders
where customer_id = $1
order by id
