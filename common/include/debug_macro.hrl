%%%-------------------------------------------------------------------
%%% @author michael <michael@donald>
%%% @copyright (C) 2013, michael
%%% @doc
%%%
%%% @end
%%% Created : 30 Dec 2013 by michael <michael@donald>
%%%-------------------------------------------------------------------

%%-define(debug, true).
-ifdef(debug).
-define(DEBUG(Format, Args),
  lager:info("~s.~w: \n" ++ Format, [ ?MODULE, ?LINE | Args])).
-else.
-define(DEBUG(Format, Args), true).
-endif.
