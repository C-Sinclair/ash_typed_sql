Library.Repo.query!("truncate reviews, loans, books, authors restart identity")

today = Date.utc_today()

books =
  for {author, title, published_on} <- [
        {"Ursula K. Le Guin", "A Wizard of Earthsea", ~D[1968-11-01]},
        {"Ursula K. Le Guin", "The Dispossessed", ~D[1974-05-01]},
        {"Octavia E. Butler", "Kindred", ~D[1979-06-01]},
        {"Italo Calvino", "Invisible Cities", ~D[1972-11-01]}
      ],
      into: %{} do
    [%{id: id}] = Library.add_book!(author, title, published_on)
    {title, id}
  end

for {title, rating, body} <- [
      {"A Wizard of Earthsea", 5, "Still the best magic school."},
      {"A Wizard of Earthsea", 4, "Ged deserved better."},
      {"The Dispossessed", 5, "An ambiguous utopia indeed."},
      {"Kindred", 5, "Could not put it down."},
      {"Invisible Cities", 4, nil}
    ] do
  Library.add_review!(books[title], rating, body)
end

for {title, borrower, due_in_days} <- [
      {"A Wizard of Earthsea", "ada", -10},
      {"The Dispossessed", "ada", 7},
      {"Kindred", "grace", -3},
      {"Invisible Cities", "grace", 14},
      {"Kindred", "linus", 21}
    ] do
  Library.lend_book!(books[title], borrower, Date.add(today, due_in_days))
end

Library.refresh_book_stats!()

IO.puts("Seeded #{map_size(books)} books, 5 reviews and 5 loans.")
