%%%-------------------------------------------------------------------
%%% @author michael <michael@donald-desktop>
%%% @copyright (C) 2014, michael
%%% @doc
%%%
%%% @end
%%% Created : 16 Mar 2014 by michael <michael@donald-desktop>
%%%-------------------------------------------------------------------
-module(common_pretty_print).
-export([pretty_print_list/1]).

%% pretty print list:

pretty_print_list(List) ->
        pretty_print_list(List, []).

pretty_print_list([H|T], Acc) ->
        pretty_print_list(T,[lager:pr(H,?MODULE)|Acc]);
pretty_print_list([], Acc) ->
        lists:reverse(Acc). 
