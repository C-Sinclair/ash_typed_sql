insert into loans (book_id, borrower, due_on)
values ($1, $2, $3)
returning *
