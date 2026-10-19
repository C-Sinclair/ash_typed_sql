insert into reviews (book_id, rating, body)
values ($1, $2, $3)
returning id, book_id, rating
