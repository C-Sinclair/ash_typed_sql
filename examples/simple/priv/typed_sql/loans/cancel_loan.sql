delete from loans
where id = $1
returning *
