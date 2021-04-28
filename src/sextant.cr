require "lmdb"
require "uuid"
require "./*"

module Sextant
  class Engine
    property index : Lmdb::Environment
    property store : Lmdb::Environment
    property dbs : Hash(String,Lmdb::Database)
    property store_dbs : Hash(String,Lmdb::Database)

    def initialize(index_path : String, store_path : String, map_size = 12_u64 * 10_u64 ** 9_u64, max_indexes = 20)
      @index = Lmdb::Environment.new(index_path, max_db_size: map_size, max_dbs: max_indexes)
      @store = Lmdb::Environment.new(store_path, max_db_size: map_size, max_dbs: 2)
      @dbs = Hash(String,Lmdb::Database).new
      @store_dbs = Hash(String,Lmdb::Database).new
    end

    def get_store_handle (name : String | Nil)
      store_dbi = @store.open_database(name, Lmdb::Flags::Database.flags(CREATE))
      store_txn = @store.open_transaction
      store_cur = store_txn.open_cursor(store_dbi)

      return BaseHandle.new(store_cur, store_txn)
    end

    def get_idx_handle(index_name : String)
      idx_dbi = @index.open_database(index_name, Lmdb::Flags::Database.flags(CREATE, DUP_SORT, DUP_FIXED))
      idx_txn = @index.open_transaction
      idx_cur = idx_txn.open_cursor(idx_dbi)
      return BaseHandle.new(idx_cur, idx_txn)
    end

    def get_idx_handle(index_name : String)
      idx_dbi = @index.open_database(index_name, Lmdb::Flags::Database.flags(CREATE, DUP_SORT, DUP_FIXED))
      idx_txn = @index.open_transaction
      idx_cur = idx_txn.open_cursor(idx_dbi)
      return BaseHandle.new(idx_cur, idx_txn)
    end

    def with_single_handle(index_name : String)
      idx_dbi = @index.open_database(index_name, Lmdb::Flags::Database.flags(CREATE, DUP_SORT, DUP_FIXED))
      idx_txn = @index.open_transaction
      idx_cur = idx_txn.open_cursor(idx_dbi)

      yield BaseHandle.new(idx_cur, idx_txn)

      idx_cur.close
      idx_txn.commit
    end

    def with_handle(index_names : Array(String), store_names = ["store","config"], read_only = true, auto_close = true)
      handles = Hash(String,Array(BaseHandle)).new
      store_handles = Hash(String,Array(BaseHandle)).new

      curs = [] of Lmdb::Cursor

      index_names.each do |handle_name|
        if !@dbs.has_key?(handle_name)
          @dbs[handle_name] = @index.open_database(handle_name, Lmdb::Flags::Database.flags(CREATE, DUP_SORT, DUP_FIXED))
        end
      end

      store_names.each do |store_name|
        if !@store_dbs.has_key?(store_name)
          @store_dbs[store_name] = @store.open_database store_name, Lmdb::Flags::Database.flags(CREATE)
        end
      end

      store_txn = @store.open_transaction read_only: read_only
      txn = @index.open_transaction read_only: read_only

      index_names.each do |handle_name|
        idx_cur = txn.open_cursor(@dbs[handle_name])
        handles[handle_name] = [BaseHandle.new(idx_cur, txn)]
      end

      store_names.each do |store_name|
        store_cur = store_txn.open_cursor(@store_dbs[store_name])
        store_handles[store_name] = [BaseHandle.new(store_cur,store_txn)]
      end

      multihandle = MultiHandle.new handles, txn,  @dbs, store_handles, store_txn, @store_dbs
      yield multihandle
#
      if auto_close
        txn.commit
        store_txn.commit
      end
    end
  end
end
#
# require "benchmark"
# include Query
# # # #
# e = Sextant::Engine.new "./testidx", "./testdb"
# e.with_handle ["playerTags","teamTags","description", "day", "metadata", "created"] do |cur|
#   puts cur.fetch_query(
#     cur.query(
#       intersection(
#         where("created").lesser(1616880577_i64),
#         where("description").equals("ball")
#       )
#     )
#   ).select(Bytes).map { |e| String.new e.as(Bytes) }.next
    # Benchmark.ips do |job|
    #   job.report("FETCH 50 EVENTS WHERE INTERSECTION()") {
    #    cur.fetch_query(
    #     cur.query(
    #       intersection(
    #         where("created").lesser(1616880577_i64),
    #         where("description").equals("ball")
    #       )
    #     )
    #   ).select(Bytes).map { |e| String.new e }.in_groups_of(50).next
    # }
  # end
  # Benchmark.ips do |job|
  #    job.report("<= 20") {
  #    cur.query(
  #       intersection(
  #         where("created").lesser(1616880577_i64),
  #         where("description").equals("ball")
  #       )).in_groups_of(100).next
  #     }
  #   }
    # job.report ("== ball (tokenization)") {
    #   cur.query(
    #       where("description").equals("ball")
    #   ).in_groups_of(100).next
    # }
    # job.report ("day > 10 and day < 60") {
    #   cur.query(
    #       where("day").in_between(10_i64,60_i64)
    #   ).in_groups_of(100).next
    # }
    # job.report ("fuzzy matching 'play ball'") {
    #   cur.query(
    #       where("description").includes("play ball")
    #   ).in_groups_of(100).next
    # }
    # job.report ("all messages from the hall monitor") {
    #   cur.query(
    #       where("metadata").equals("being_1")
    #   ).in_groups_of(100).next
    # }
#   end
# end
