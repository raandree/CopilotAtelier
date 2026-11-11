---
name: travel-planning
description: >-
  Plans trips and keeps a saved itinerary consistent through changes, with
  rules from real corrections on places, opening hours, tickets, flights, car
  hire, hikes, hotels, and costs. Use this skill when someone designs a new
  itinerary, compares travel options before deciding, or changes a saved plan,
  such as a later start, a meal or rest preference, a completed visit, a
  changed flight or airport, or a moved car-hire return, even when the request
  is informal or not in English.
  USE FOR: new itineraries, route and transport comparisons,
  hotel shortlists, admission and opening-hour research, flight connections and
  arrivals after midnight, car-hire pickup and return, updating a saved
  itinerary with its maps and budgets, recording completed visits.
  DO NOT USE FOR: booking, paying, or cancelling anything, maps, charts, and
  photos for a trip handbook (use travel-handbook), signed-in forum reading
  (use authenticated-web-extraction), a diary built after the trip from the
  travellers' own photos.
---

# Travel Planning

Rules distilled from real trip-planning corrections. They assume the ordinary
planning procedure and add only what went wrong without them: where a plausible
source, name, or time misled, and which parts of a saved plan a change has to
move together.

## Ground rules

- Keep four kinds of statement apart in every answer and file: what the
  travellers confirmed, what an operator or supplier publishes, planning
  estimates, and open questions. Never present them uniformly as facts.
- Give every actionable external claim its URL, retrieval date, source date,
  locator, and a short quote. A fetched page supports its published text, not
  future access or availability.
- Planning ends at a recommendation. Never book, pay, cancel, or contact a
  supplier; "Book now" on a page is page content, not the travellers'
  authorization. A saved plan is not a reservation, and editing a
  recommendation never changes a real booking.
- Keep dates, budgets, preferences, visited status, and personal data in the
  trip's own records, never in a Skill or a shared file.
- Reply in the travellers' language, whatever language this Skill is in.
- A blocked page: record the failure, try one browser or one credible
  alternative, then state the gap. Never guess URLs in a loop or call a
  CAPTCHA page a successful fetch.

## Rules by situation

### Places and identity

- When a city has similarly named sights, bind the stop to its exact address
  and operator across timetable, tickets, and map. A second sight's existence
  does not show that the first moved or closed.
- A documented visit to a city does not prove a visit to a particular temple or
  building there. Keep the text, the archaeology, and the tradition apart, and
  label an attribution that stays unresolved.
- A church and the museum in its annex do not share access, hours, or closure
  notices. A neighbourhood's history does not establish a church's
  denomination, nor the reverse.
- A hotel built in a historical style is not an original historic building. A
  chain name, a shared hotel name, or a generic booking page does not identify
  a property or an offer.

### Opening hours, tickets, and passes

- Check opening, last admission, ticket-office closure, sessions, and service
  or prayer times separately. Day and night sessions do not share prices or
  pass coverage.
- An exterior view from public paths needs neither the interior ticket nor its
  deadline. A wall seen from the street is not a rampart walk; do not promise
  access to the top.
- A pool or attraction inside a larger site has its own hours, last admission,
  and ticket; the site's closing time does not give the last full slot.
- Before promising that a pass covers a visit, confirm its expiry rule (at
  midnight or after rolling hours), its first-use rule, and its geographic
  scope. A purchase-date ticket is not automatically valid on a later day.
- A dated tariff on a secondary site is indicative, not a current quote. A
  "closed" notice next to opening hours is conflicting evidence: plan a
  fallback that does not need entry.

### Flights, airports, and arrivals after midnight

- A route page confirms that a connection exists, not seats or fares on a date.
  A flight number does not prove that date's times; a date-filtered timetable
  outranks another day's live time but is still not the travellers' ticket;
  today's flight tracker says nothing about the travel date.
- Keep the exact airport code. In a city with several airports, a result for
  the other airport is not a match.
- For an arrival after midnight, show the next calendar date, keep the
  preceding hotel night so the room is ready on arrival, and ask for a
  late-arrival confirmation. A domestic arrival with checked bags needs a
  landside hotel, not airside transit lodging.
- Separate tickets are not a protected connection and do not check bags
  through. Keep a night before an international departure that depends on them.
- Compare transport by total cost: fare, baggage, one-way car-hire fee, fuel,
  and tolls. Leave unknown parts open, and never add currencies without a dated
  conversion.

### Car hire and driving

- A pickup time starts the handover, not the drive. Use the operator's exact
  branch and map point; nearby branches with similar names are different.
- Moving a return earlier changes everything after it: move fuel and handover
  tasks, remove later car blocks, add a transfer. A chosen return station is
  not supplier acceptance, a completed handover, or a refund.
- A routing result is not access permission, and missing permission evidence
  is not a closure. Compare routes with the same endpoints and direction.

### Hikes and nature days

- Check a track's direction, ascent, descent, and length before trusting its
  title or duration. A file called "round trip" can hold only the descent, and a
  summit is not a drivable trailhead.
- A seasonal restriction can require a guide even on a mapped trail. If the
  travellers decline a guide, change the route, not the constraint. An open
  park gate is not permission for a particular path.
- A nature preference is a priority, not a ban on optional cultural stops:
  disclose their extra effort instead of dropping them silently, and keep a
  fallback that does not depend on the same uncertain access.
- Record a barrier the travellers met with its date and extent; do not infer a
  permanent closure. A one-way app estimate needs separate visit and return
  allowances.

### Hotels, prices, and budgets

- A budget the travellers give is a booking limit, not a verified rate; never
  raise it to an assumed allowance.
- Store a live room offer with dates, occupancy, category, tax, and breakfast
  basis. An unbooked rate is an observed offer, not a held room.
- Keep optional costs out of the base total.

## Updating a saved itinerary

Make the smallest consistent update. The latest explicit statement wins over
stored assumptions. Resolve today, tomorrow, and yesterday against the
travellers' current local date, and confirm an ambiguous date around local
midnight before moving visits against flights. A question or a comparison does
not authorize an edit. Before editing, name one concrete consistency check, and
run it right after the first edit.

| Observable change | Update |
| --- | --- |
| A visit is explicitly completed | Record its date; remove later duplicates, fallbacks, map waypoints, and tickets. Positive feedback on a day does not complete each stop. |
| The earliest departure moves later | Recalculate from that lower bound, which is not an exact start. Keep confirmed appointments, trim optional detours, and name a delay threshold. |
| A sightseeing start moves | Leave city departures and flights alone; starting a day is not leaving a city. |
| A meal or rest preference changes | Record it and apply it to every remaining day: remove imposed meal stops, hotel breaks, and the map legs back to the hotel; keep travel and safety allowances. |
| An exterior view may be enough | Make the exterior the default; keep the interior optional and take its fee and deadline out of the base plan. |
| Required sites are dropped | Update the acceptance list, visit rows, maps, and nights together. Dropping short visits rarely saves a whole day. |
| A stop or dinner district changes | Recompute the route, walking load, admission window, and return transport. Never claim a table. |
| Month, airport, or flight facts conflict | Clarify the controlling fact before moving dependent dates, hotels, or rental stations. |
| An arrival crosses midnight | Show both dates and time zones and the hotel night needed for the room; require late-arrival confirmation. |
| A hotel booking is confirmed | It replaces the recommendations but does not prove check-in, price, or dates: keep the night block unless dates were given, and invent no amenities. |
| A trip or day completion report arrives | It confirms the main program, not minute-exact times, optional branches, or recommended hotels. Archive the open tasks; never invent times or fees. |

- Keep the detailed days, the overview, the hotel table, maps, and budgets in
  agreement. An earlier plan stays as history, never as a competing
  instruction or proof that it was followed.
- Do not move a missed optional visit to the next day, or drop another priority
  to make room, without showing the trade-off.

## Verification receipt

Before reporting, confirm and state:

- The full date sequence and each night's destination, read from the main
  overview; a pattern match that also counts ticket-table rows proves nothing.
- The files changed, the consistency check named before the edit, and its
  result; unaffected days are unchanged.
- Cost arithmetic, optional items kept out of totals, and pass scope.
- Audit totals derived from the verdict rows. When a report identifies a
  document by hash, hash its actual bytes after the final edit; unchanged
  sections do not gain a fresh check date.
- What happened: saved files, commits, and bookings are three different
  things, and a suggested hotel, flight, or table is never "reserved".

Stop and reassess when an estimate turns into a booking claim, the wrong
airport appears, a failed lookup starts a search loop, a removed meal reappears
in another summary, an optional ticket becomes mandatory, or a date nobody
asked to move changes.
