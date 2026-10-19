insert into shelf.loans (book_id, member_id, due_on)
values ($1, $2, current_date + $3::integer)
returning id, book_id, member_id, borrowed_on, due_on
