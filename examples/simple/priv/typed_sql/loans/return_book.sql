update loans set returned_on = current_date
where id = $1 and returned_on is null
returning *
