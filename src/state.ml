open Holdem

type t = {
  deck : card list;
  players : player list;
  pot : int;
  buy_in : int;
  board : card list;
  active : bool;
  position : int;
  min_bet : int;
  last_min_bet : int;
  confirmed : bool;
  round_finisher : int;
  rounds_played : int;
}

type result =
  | Legal of t
  | Illegal of string

let init buy_in =
  {
    deck = shuffled_deck ();
    players = [];
    pot = 0;
    buy_in;
    board = [];
    active = false;
    position = 0;
    min_bet = buy_in / 100;
    last_min_bet = 0;
    confirmed = false;
    round_finisher = 0;
    rounds_played = 0;
  }

let comfirm st =
  if (not st.active) || st.confirmed then
    Illegal "Error: Please Enter a Command!\n"
  else
    Legal
      {
        deck = st.deck;
        players = st.players;
        pot = st.pot;
        buy_in = st.buy_in;
        board = st.board;
        active = st.active;
        position = st.position;
        min_bet = st.min_bet;
        last_min_bet = st.last_min_bet;
        confirmed = true;
        round_finisher = st.round_finisher;
        rounds_played = st.rounds_played;
      }

let equals p1 p2 = p1.name = p2.name

(** [nth_player players n] safely gets the [n]th player and wraps around if
    needed *)
let nth_player (players : Holdem.player list) (n : int) =
  let len = List.length players in
  let pos = if n >= len then n mod len else if n < 0 then n + len else n in
  List.nth players pos

let update_pos st =
  let len = List.length st.players in
  let pos = ref ((1 + st.position) mod len) in
  let () =
    while
      (not (nth_player st.players !pos).active)
      || (nth_player st.players !pos).balance = 0
    do
      let new_pos = (!pos + 1) mod len in
      pos := new_pos
    done
  in
  !pos

let current_player st =
  let len = List.length st.players in
  let pos = st.position mod len in
  nth_player st.players pos

let last_active_player st =
  let rec last_active_player_aux (players : Holdem.player list) : player =
    match players with
    | [] -> failwith "Impossible: No Active Players"
    | p :: t -> if p.active then p else last_active_player_aux t
  in
  last_active_player_aux (List.rev st.players)

let betting_round_over st player =
  equals (nth_player st.players st.round_finisher) player

let small_blind_player st =
  let len = List.length st.players in

  let pos = (len - 2 + st.position) mod len in
  nth_player st.players pos

let big_blind_player st =
  let len = List.length st.players in
  let pos = (len - 1 + st.position) mod len in
  nth_player st.players pos

let update_players st player =
  List.map (fun p -> if equals p player then player else p) st.players

let deal_to_player p st =
  let card1 = Holdem.top_card st.deck in
  let deck1 = Holdem.draw_from_deck st.deck in
  let card2 = Holdem.top_card deck1 in
  let pot = ref st.pot in
  let player =
    if p.balance < st.buy_in / 200 then
      let () = pot := !pot + p.balance in
      Holdem.bet_amount p.balance p
    else if small_blind_player st |> equals p then
      let () = pot := !pot + (st.buy_in / 200) in
      Holdem.bet_amount (st.buy_in / 200) p
    else if big_blind_player st |> equals p then
      let () = pot := !pot + (st.buy_in / 100) in
      Holdem.bet_amount (st.buy_in / 100) p
    else p
  in
  let players =
    Holdem.deal_to card1 player |> Holdem.deal_to card2 |> update_players st
  in
  {
    deck = Holdem.draw_from_deck deck1;
    players;
    pot = !pot;
    buy_in = st.buy_in;
    board = st.board;
    active = true;
    position = st.position;
    min_bet = st.min_bet;
    last_min_bet = st.last_min_bet;
    confirmed = st.confirmed;
    round_finisher = st.round_finisher;
    rounds_played = st.rounds_played;
  }

let active_player_filter (player : player) : bool = player.active

let amount_to_take st player num_winners =
  let amt = ref 0 in
  let pos = ref 0 in
  let () =
    while !pos < List.length st.players do
      let p = nth_player st.players !pos in
      amt := !amt + min p.betting player.betting;
      pos := !pos + 1
    done
  in
  !amt / num_winners

let reset_state st =
  let pos = ref (List.length st.players - 1) in
  let players = ref [] in
  let () =
    while !pos >= 0 do
      let player = nth_player st.players !pos in
      let p =
        {
          name = player.name;
          balance = player.balance;
          betting = 0;
          active = true;
          hand = [];
        }
      in
      players := p :: !players;
      pos := !pos - 1
    done
  in
  {
    deck = shuffled_deck ();
    players = !players;
    pot = 0;
    buy_in = st.buy_in;
    board = [];
    active = false;
    position = (st.rounds_played + 1) mod List.length !players;
    min_bet = st.buy_in / 100;
    last_min_bet = 0;
    confirmed = false;
    round_finisher = 0;
    rounds_played = st.rounds_played + 1;
  }

let cash_out st player num_winners =
  let amt = amount_to_take st player num_winners in
  let cashed_out_player =
    {
      name = player.name;
      balance = player.balance + amt;
      betting = player.betting;
      active = false;
      hand = player.hand;
    }
  in
  let pos = ref (List.length st.players - 1) in
  let players = ref [] in
  let () =
    while !pos >= 0 do
      let player = nth_player st.players !pos in
      let p =
        if equals player cashed_out_player then cashed_out_player
        else
          {
            name = player.name;
            balance = player.balance;
            betting = max 0 (player.betting - cashed_out_player.betting);
            active = player.active;
            hand = player.hand;
          }
      in
      players := p :: !players;
      pos := !pos - 1
    done
  in
  Printf.printf "%s won %i with %s \n" player.name amt
    (cards_to_string player.hand);
  {
    deck = st.deck;
    players = !players;
    pot = st.pot - amt;
    buy_in = st.buy_in;
    board = st.board;
    active = st.active;
    position = st.position;
    min_bet = st.min_bet;
    last_min_bet = st.last_min_bet;
    confirmed = st.confirmed;
    round_finisher = st.round_finisher;
    rounds_played = st.rounds_played;
  }

let give_money_back st =
  let pos = ref (List.length st.players - 1) in
  let players = ref [] in
  let () =
    while !pos >= 0 do
      let player = nth_player st.players !pos in
      let p =
        {
          name = player.name;
          balance = player.balance + player.betting;
          betting = 0;
          active = true;
          hand = [];
        }
      in
      players := p :: !players;
      pos := !pos - 1
    done
  in
  Legal
    {
      deck = shuffled_deck ();
      players = !players;
      pot = 0;
      buy_in = st.buy_in;
      board = [];
      active = false;
      position = (st.rounds_played + 1) mod List.length !players;
      min_bet = st.buy_in / 100;
      last_min_bet = 0;
      confirmed = false;
      round_finisher = 0;
      rounds_played = st.rounds_played + 1;
    }

let rec find_winners st =
  let state = ref st in
  let active_players = List.filter active_player_filter st.players in
  let winners = Showdown.showdown st.board active_players in
  let len = List.length winners in
  if len = 0 then give_money_back st
  else
    let sorted_winners =
      ref (List.sort (fun a b -> Stdlib.compare a.betting b.betting) winners)
    in
    let () =
      while List.length !sorted_winners >= 1 do
        state := cash_out !state (List.hd !sorted_winners) len;
        sorted_winners := List.tl !sorted_winners
      done
    in
    if !state.pot > 0 then find_winners !state else Legal (reset_state !state)

let deal st =
  if st.active then Illegal "Error: The cards have already been dealt!\n"
  else if List.length st.players < 2 then
    Illegal "Error: There must be at least 2 players to start playing!\n"
  else
    let state =
      List.fold_left (fun st p -> deal_to_player p st) st st.players
    in
    Legal
      {
        deck = state.deck;
        players = state.players;
        pot = state.pot;
        buy_in = state.buy_in;
        board = state.board;
        active = state.active;
        position = state.position;
        min_bet = state.min_bet;
        last_min_bet = 0;
        confirmed = state.confirmed;
        round_finisher =
          (List.length state.players - 1 + st.rounds_played)
          mod List.length state.players;
        rounds_played = st.rounds_played;
      }

let reset_finisher st =
  let len = List.length st.players in
  let pos = ref ((len - 3) mod len) in
  let () =
    while not (nth_player st.players !pos).active do
      let new_pos = (!pos - 1) mod len in
      pos := new_pos
    done
  in
  {
    deck = st.deck;
    players = st.players;
    pot = st.pot;
    buy_in = st.buy_in;
    board = st.board;
    active = st.active;
    position = st.position;
    min_bet = st.min_bet;
    last_min_bet = st.last_min_bet;
    confirmed = st.confirmed;
    round_finisher = !pos;
    rounds_played = st.rounds_played;
  }

let reset_start_pos st =
  let st_temp =
    {
      deck = st.deck;
      players = st.players;
      pot = st.pot;
      buy_in = st.buy_in;
      board = st.board;
      active = st.active;
      position = List.length st.players - 3;
      min_bet = st.min_bet;
      last_min_bet = st.last_min_bet;
      confirmed = st.confirmed;
      round_finisher = st.round_finisher;
      rounds_played = st.rounds_played;
    }
  in
  let position = update_pos st_temp in
  {
    deck = st.deck;
    players = st.players;
    pot = st.pot;
    buy_in = st.buy_in;
    board = st.board;
    active = st.active;
    position;
    min_bet = st.min_bet;
    last_min_bet = st.last_min_bet;
    confirmed = st.confirmed;
    round_finisher = st.round_finisher;
    rounds_played = st.rounds_played;
  }

let update_last_min_bet st =
  {
    deck = st.deck;
    players = st.players;
    pot = st.pot;
    buy_in = st.buy_in;
    board = st.board;
    active = st.active;
    position = st.position;
    min_bet = st.min_bet;
    last_min_bet = st.min_bet;
    confirmed = st.confirmed;
    round_finisher = st.round_finisher;
    rounds_played = st.rounds_played;
  }

let deal_to_board st =
  let board = st.board @ [ Holdem.top_card st.deck ] in
  {
    deck = Holdem.draw_from_deck st.deck;
    players = st.players;
    pot = st.pot;
    buy_in = st.buy_in;
    board;
    active = st.active;
    position = st.position;
    min_bet = st.min_bet;
    last_min_bet = st.last_min_bet;
    confirmed = st.confirmed;
    round_finisher = st.round_finisher;
    rounds_played = st.rounds_played;
  }
  |> reset_finisher |> reset_start_pos |> update_last_min_bet

let deal_flop st = st |> deal_to_board |> deal_to_board |> deal_to_board

let rec active_player_count (players : player list) =
  match players with
  | [] -> 0
  | h :: t ->
      if h.active then 1 + active_player_count t else active_player_count t

let call st =
  if not st.active then Illegal "Error: The cards have not been dealt yet!\n"
  else if not st.confirmed then Illegal "Error: Please confirm your turn!\n"
  else
    let player = current_player st in
    if st.min_bet = player.betting then
      Illegal "Error: Cannot call when no one has bet!\n"
    else
      let amt =
        if st.min_bet >= player.betting + player.balance then player.balance
        else st.min_bet - player.betting
      in
      let players = player |> Holdem.bet_amount amt |> update_players st in
      if betting_round_over st player then
        let len = List.length st.board in
        if len = 5 then find_winners st
        else
          let state = if len = 0 then deal_flop st else deal_to_board st in
          Legal
            {
              deck = state.deck;
              players;
              pot = st.pot + amt;
              buy_in = st.buy_in;
              board = state.board;
              active = st.active;
              position = update_pos st;
              min_bet = st.min_bet;
              last_min_bet = st.last_min_bet;
              confirmed = false;
              round_finisher = state.round_finisher;
              rounds_played = st.rounds_played;
            }
      else
        Legal
          {
            deck = st.deck;
            players;
            pot = st.pot + amt;
            buy_in = st.buy_in;
            board = st.board;
            active = st.active;
            position = update_pos st;
            min_bet = st.min_bet;
            last_min_bet = st.last_min_bet;
            confirmed = false;
            round_finisher = st.round_finisher;
            rounds_played = st.rounds_played;
          }

let check st =
  if not st.active then Illegal "Error: The cards have not been dealt yet!\n"
  else if not st.confirmed then Illegal "Error: Please confirm your turn!\n"
  else
    let player = current_player st in
    if st.min_bet - player.betting > 0 then
      Illegal "Error: You cannot check here!\n"
    else if betting_round_over st player then
      let len = List.length st.board in
      if len = 5 then find_winners st
      else
        let state = if len = 0 then deal_flop st else deal_to_board st in
        Legal
          {
            deck = state.deck;
            players = st.players;
            pot = st.pot;
            buy_in = st.buy_in;
            board = state.board;
            active = st.active;
            position = update_pos st;
            min_bet = st.min_bet;
            last_min_bet = st.last_min_bet;
            confirmed = false;
            round_finisher = state.round_finisher;
            rounds_played = st.rounds_played;
          }
    else
      Legal
        {
          deck = st.deck;
          players = st.players;
          pot = st.pot;
          buy_in = st.buy_in;
          board = st.board;
          active = st.active;
          position = update_pos st;
          min_bet = st.min_bet;
          last_min_bet = st.last_min_bet;
          confirmed = false;
          round_finisher = st.round_finisher;
          rounds_played = st.rounds_played;
        }

let fold st =
  if not st.active then Illegal "Error: The cards have not been dealt yet!\n"
  else if not st.confirmed then Illegal "Error: Please confirm your turn!\n"
  else
    let p = current_player st in
    let player =
      {
        name = p.name;
        balance = p.balance;
        betting = p.betting;
        active = false;
        hand = p.hand;
      }
    in
    let players = update_players st player in
    if active_player_count players = 1 then find_winners st
    else if betting_round_over st player then
      let len = List.length st.board in
      if len = 5 then find_winners st
      else
        let state = if len = 0 then deal_flop st else deal_to_board st in
        Legal
          {
            deck = state.deck;
            players;
            pot = st.pot;
            buy_in = st.buy_in;
            board = state.board;
            active = st.active;
            position = update_pos st;
            min_bet = st.min_bet;
            last_min_bet = st.last_min_bet;
            confirmed = false;
            round_finisher = state.round_finisher;
            rounds_played = st.rounds_played;
          }
    else
      Legal
        {
          deck = st.deck;
          players;
          pot = st.pot;
          buy_in = st.buy_in;
          board = st.board;
          active = st.active;
          position = update_pos st;
          min_bet = st.min_bet;
          last_min_bet = st.last_min_bet;
          confirmed = false;
          round_finisher = st.round_finisher;
          rounds_played = st.rounds_played;
        }

let raise st i =
  if not st.active then Illegal "Error: The cards have not been dealt yet!\n"
  else if not st.confirmed then Illegal "Error: Please confirm your turn!\n"
  else if i < st.min_bet + (st.buy_in / 100) then
    Illegal
      ("Error: You are raising by an amount that is too small! Minimum amount \
        to bet is "
      ^ string_of_int (st.min_bet + (st.buy_in / 100))
      ^ "\n")
  else
    let p = current_player st in
    let effective_bet = i + st.min_bet - p.betting in
    if effective_bet > p.balance then
      Illegal "Error: You do not have enough to raise by that amount!"
    else
      let player = bet_amount effective_bet p in
      let players = update_players st player in
      let len = List.length st.players in
      let finsher_pos = ref ((st.position - 1) mod len) in
      let () =
        while not (nth_player st.players !finsher_pos).active do
          let new_pos = (!finsher_pos - 1) mod len in
          finsher_pos := new_pos
        done
      in
      Legal
        {
          deck = st.deck;
          players;
          pot = st.pot + effective_bet;
          buy_in = st.buy_in;
          board = st.board;
          active = st.active;
          position = update_pos st;
          min_bet = st.min_bet + i;
          last_min_bet = st.last_min_bet;
          confirmed = false;
          round_finisher = !finsher_pos;
          rounds_played = st.rounds_played;
        }

let add name st =
  if st.active then Illegal "Error: Players cannot be added mid-round!\n"
  else if List.exists (fun p -> p.name = name) st.players then
    Illegal "Error: Name already being used!\n"
  else
    let p = Holdem.make_player name st.buy_in in
    Legal
      {
        deck = st.deck;
        players = p :: st.players;
        pot = st.pot;
        buy_in = st.buy_in;
        board = st.board;
        active = st.active;
        position = st.position;
        min_bet = st.min_bet;
        last_min_bet = st.last_min_bet;
        confirmed = st.confirmed;
        round_finisher = st.round_finisher;
        rounds_played = st.rounds_played;
      }

let remove name st =
  if st.active then Illegal "Error: Players cannot be added mid-round!\n"
  else if List.exists (fun p -> p.name = name) st.players then
    Legal
      {
        deck = st.deck;
        players = List.filter (fun p -> p.name <> name) st.players;
        pot = st.pot;
        buy_in = st.buy_in;
        board = st.board;
        active = st.active;
        position = st.position;
        min_bet = st.min_bet;
        last_min_bet = st.last_min_bet;
        confirmed = st.confirmed;
        round_finisher = st.round_finisher;
        rounds_played = st.rounds_played;
      }
  else Illegal "Error: Name does not exist in list of players!\n"

let action cmd (st : t) : result =
  match cmd with
  | Command.Comfirm -> comfirm st
  | Command.Deal -> deal st
  | Command.Call -> call st
  | Command.Check -> check st
  | Command.Fold -> fold st
  | Command.Raise i -> raise st i
  | Command.AddPlayer name -> add name st
  | Command.RemovePlayer name -> remove name st

let rec winners_to_string names =
  match names with
  | [ h1; h2 ] -> h1 ^ ", and " ^ h2
  | [ h1 ] -> h1
  | h1 :: t -> h1 ^ ", " ^ winners_to_string t
  | [] -> ""

let quit st =
  let amt = List.fold_left max 0 (List.map (fun p -> p.balance) st.players) in
  let winners = List.filter (fun p -> p.balance = amt) st.players in
  let winner_names = List.map (fun p -> p.name) winners in
  winners_to_string winner_names
  ^ " won with an amount of " ^ string_of_int amt ^ ".\n\n"

let rec players_to_string players =
  match players with
  | [ h ] -> Holdem.player_to_string h ^ "\n"
  | h :: t -> Holdem.player_to_string h ^ "\n" ^ players_to_string t
  | [] -> "No current players\n"

let rec repeat_string n str =
  if n <= 0 then "" else str ^ repeat_string (n - 1) str

let top_of_card (board : card list) =
  let n = 5 - List.length board in
  repeat_string n " ┌─────────┐ "

let bottom_of_card (board : card list) =
  let n = 5 - List.length board in
  repeat_string n " └─────────┘ "

let middle_of_card (board : card list) =
  let n = 5 - List.length board in
  repeat_string n " │░░░░░░░░░│ "

let unknown_cards_to_string (board : card list) =
  "\n" ^ top_of_card board ^ "\n" ^ middle_of_card board ^ "\n"
  ^ middle_of_card board ^ "\n" ^ middle_of_card board ^ "\n"
  ^ middle_of_card board ^ "\n" ^ middle_of_card board ^ "\n"
  ^ middle_of_card board ^ "\n" ^ middle_of_card board ^ "\n"
  ^ bottom_of_card board

let state_to_string st =
  "TABLE:\n"
  ^ players_to_string st.players
  ^ "Pot: " ^ string_of_int st.pot ^ " Chips\n" ^ "Board: (Min Bet: "
  ^ string_of_int st.min_bet ^ ")"
  ^
  if String.equal (Holdem.cards_to_string st.board) "" then
    unknown_cards_to_string st.board
    ^ "\n\n"
    ^
    if st.active then
      let player = current_player st in
      if st.confirmed then revealed_player_to_string player
      else
        Holdem.player_to_string player
        ^ ", are you ready? Press enter to start your turn."
    else
      "You can add/remove players or deal cards (enter \"help\" for exact \
       commands)"
  else
    Holdem.cards_to_string st.board
    ^ "\n\n"
    ^
    if st.active then
      let player = current_player st in
      if st.confirmed then revealed_player_to_string player
      else
        Holdem.player_to_string player
        ^ ", are you ready? Press enter to start your turn."
    else
      "You can add/remove players or deal cards (enter \"help\" for exact \
       commands)"
