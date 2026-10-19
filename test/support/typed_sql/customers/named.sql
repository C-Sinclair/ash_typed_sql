select name from customers
where $1::text is null or lower(name) = lower($1)
order by name
limit $2
