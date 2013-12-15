{application,defrag,
             [{description,"packet defragmentation engine"},
              {vsn,"0.0.1"},
              {registered,[defrag_server,defrag_root_sup]},
              {applications,[kernel]},
              {mod,{defrag_app,[]}},
              {modules,[defrag_app,defrag_root_sup,defrag_server,
                        defrag_worker]}]}.
