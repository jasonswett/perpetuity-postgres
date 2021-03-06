require 'perpetuity/postgres'
require 'perpetuity/postgres/table/attribute'
require 'perpetuity/attribute'
require 'perpetuity/postgres/serialized_data'

module Perpetuity
  describe Postgres do
    let(:postgres) { Postgres.new(db: 'perpetuity_gem_test') }

    describe 'initialization params' do
      context 'with params' do
        let(:host)      { double('host') }
        let(:port)      { double('port') }
        let(:db)        { double('db') }
        let(:pool_size) { double('pool size') }
        let(:username)  { double('username') }
        let(:password)  { double('password') }
        let(:postgres) do
          Postgres.new(
            host:      host,
            port:      port,
            db:        db,
            pool_size: pool_size,
            username:  username,
            password:  password
          )
        end
        subject { postgres }

        its(:host)      { should == host }
        its(:port)      { should == port }
        its(:db)        { should == db }
        its(:pool_size) { should == pool_size }
        its(:username)  { should == username }
        its(:password)  { should == password }
      end

      context 'default values' do
        let(:postgres) { Postgres.new(db: 'my_db') }
        subject { postgres }

        its(:host)      { should == 'localhost' }
        its(:port)      { should == 5432 }
        its(:pool_size) { should == 5 }
        its(:username)  { should == ENV['USER'] }
        its(:password)  { should be_nil }
      end
    end

    it 'creates and drops tables' do
      postgres.create_table 'Article', [
        Postgres::Table::Attribute.new('title', String, max_length: 40),
        Postgres::Table::Attribute.new('body', String),
        Postgres::Table::Attribute.new('author', Object)
      ]
      postgres.should have_table('Article')

      postgres.drop_table 'Article'
      postgres.should_not have_table 'Article'
    end

    it 'converts values into something that works with the DB' do
      postgres.postgresify("string").should == "'string'"
      postgres.postgresify(1).should == '1'
      postgres.postgresify(true).should == 'TRUE'
    end

    describe 'working with data' do
      let(:attributes) { [Attribute.new(:name, String)] }
      let(:data) { [Postgres::SerializedData.new([:name], ["'Jamie'"])] }

      it 'inserts data and finds by id' do
        id = postgres.insert('User', data, attributes).first
        result = postgres.find('User', id)

        id.should =~ /[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}/
        result['name'].should == 'Jamie'
      end

      it 'returns the ids of all items saved' do
        self.data << Postgres::SerializedData.new([:name], ["'Jessica'"]) <<
                     Postgres::SerializedData.new([:name], ["'Kevin'"])
        ids = postgres.insert('User', data, attributes)
        ids.should be_a Array
        ids.should have(3).items
      end

      it 'counts objects' do
        expect { postgres.insert 'User', data, attributes }.to change { postgres.count('User') }.by 1
      end

      it 'returns a count of 0 when the table does not exist' do
        postgres.drop_table 'Article'
        postgres.count('Article').should == 0
      end

      it 'returns no rows when the table does not exist' do
        postgres.drop_table 'Article'
        postgres.retrieve('Article', 'TRUE').should == []
      end

      it 'deletes all records' do
        postgres.insert 'User', data, attributes
        postgres.delete_all 'User'
        postgres.count('User').should == 0
      end
    end

    describe 'query generation' do
      it 'creates SQL queries with a block' do
        postgres.query { |o| o.name == 'foo' }.to_db.should ==
          "name = 'foo'"
      end

      it 'does not allow SQL injection' do
        query = postgres.query { |o| o.name == "' OR 1; --" }.to_db
        query.should == "name = '\\' OR 1; --'"
      end

      it 'limits results' do
        query = postgres.query
        sql = postgres.select(from: 'Article', where: query, limit: 2)
        sql.should == %Q{SELECT * FROM "Article" WHERE TRUE LIMIT 2}
      end

      describe 'ordering results' do
        it 'orders results without a qualifier' do
          sql = postgres.select(from: 'Article', order: :title)
          sql.should == %Q{SELECT * FROM "Article" ORDER BY title}
        end

        it 'orders results with asc' do
          sql = postgres.select(from: 'Article', order: { title: :asc })
          sql.should == %Q{SELECT * FROM "Article" ORDER BY title ASC}
        end

        it 'reverse-orders results' do
          sql = postgres.select(from: 'Article', order: { title: :desc })
          sql.should == %Q{SELECT * FROM "Article" ORDER BY title DESC}
        end
      end
    end
  end
end
