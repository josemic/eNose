-module(stream_worker_tests).

-include_lib("pkt/include/pkt.hrl").
-include_lib("eunit/include/eunit.hrl").

stream_worker_test_() ->
    [
        compare32_1(),
        compare32_2(),
        compare32_3(),
        compare32_4(),
        compare32_5(),
        compare32_6(),
        compare32_7(),
        compare32_8(),
        smaller32_1(),
        smaller32_2(),
        smaller32_3(),
        smaller32_4(),
        smaller32_5(),
        smaller32_6(),
        smaller_or_equal32_1(),
        smaller_or_equal32_2(),
        smaller_or_equal32_3(),
        smaller_or_equal32_4(),
        smaller_or_equal32_5(),
        smaller_or_equal32_6()
    ].


compare32_1() ->
    ?_assertEqual(
        less, stream_worker:compare32(1,2)
    ).

compare32_2() ->
    ?_assertEqual(
        less, stream_worker:compare32(16#FFFFFFFF-1,16#FFFFFFFF)
    ).

compare32_3() ->
    ?_assertEqual(
        less, stream_worker:compare32(16#FFFFFFFF,0)
    ).

compare32_4() ->
    ?_assertEqual(
        greater, stream_worker:compare32(2,1)
    ).

compare32_5() ->
    ?_assertEqual(
        greater, stream_worker:compare32(16#FFFFFFFF,16#FFFFFFFF-1)
    ).

compare32_6()->
    ?_assertEqual(
        equal, stream_worker:compare32(16#FFFFFFFF,16#FFFFFFFF)
    ).

compare32_7()->
    ?_assertEqual(
        less, stream_worker:compare32(4294529824, 504)
    ).

compare32_8()->
    ?_assertEqual(
        greater, stream_worker:compare32(504, 4294529824)
    ).


smaller32_1() ->
    ?_assertEqual(
        true, stream_worker:smaller32(1,2)
    ).

smaller32_2() ->
    ?_assertEqual(
        true, stream_worker:smaller32(16#FFFFFFFF-1,16#FFFFFFFF)
    ).

smaller32_3() ->
    ?_assertEqual(
        true, stream_worker:smaller32(16#FFFFFFFF,0)
    ).

smaller32_4() ->
    ?_assertEqual(
        false, stream_worker:smaller32(2,1)
    ).

smaller32_5() ->
    ?_assertEqual(
        false, stream_worker:smaller32(16#FFFFFFFF,16#FFFFFFFF-1)
    ).

smaller32_6()->
    ?_assertEqual(
        false, stream_worker:smaller32(16#FFFFFFFF,16#FFFFFFFF)
    ).

smaller_or_equal32_1() ->
    ?_assertEqual(
        true, stream_worker:smaller_or_equal32(1,2)
    ).

smaller_or_equal32_2() ->
    ?_assertEqual(
        true, stream_worker:smaller_or_equal32(16#FFFFFFFF-1,16#FFFFFFFF)
    ).

smaller_or_equal32_3() ->
    ?_assertEqual(
        true, stream_worker:smaller_or_equal32(16#FFFFFFFF,0)
    ).

smaller_or_equal32_4() ->
    ?_assertEqual(
        false, stream_worker:smaller_or_equal32(2,1)
    ).

smaller_or_equal32_5() ->
    ?_assertEqual(
        false, stream_worker:smaller_or_equal32(16#FFFFFFFF,16#FFFFFFFF-1)
    ).

smaller_or_equal32_6()->
    ?_assertEqual(
        true, stream_worker:smaller_or_equal32(16#FFFFFFFF,16#FFFFFFFF)
    ).

