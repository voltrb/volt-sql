require 'spec_helper'

describe Volt::Sql::TableReconcile do
  let(:db_adapter) { Volt::DataStore.fetch }
  let(:db) { db_adapter.db }
  before do
    # Access store, so we trigger cleanup after
    store
  end

  it 'should create a table when a new model is defined' do
    expect(db.tables).to_not include(:sample_model1)

    class SampleModel1 < Volt::Model
      temporary
    end

    # Get the db to trigger the reconcile
    db_adapter.db
    expect(db.tables).to include(:sample_model1s)
  end

  it 'should assign the right types to fields' do
    class SampleModel2 < Volt::Model
      temporary

      field :name, String
      field :title, String, size: 50
      field :place, String, nil: false
      field :created_at, Time
      field :count, Fixnum
      field :cash, Float
      field :is_admin, Volt::Boolean
    end

    adapter = db_adapter.adapter

    reconcile = Volt::Sql::TableReconcile.new(db, SampleModel2)
    reconcile.run
    db_fields = reconcile.db_fields_for_table(:sample_model2s)

    schema = {
      :id=>{:db_type=>"text", :default=>nil, :allow_null=>false, :primary_key=>false, :type=>:string, :ruby_default=>nil},
      :extra=>{:db_type=>"json", :default=>nil, :allow_null=>true, :primary_key=>false, :type=>:json, :ruby_default=>nil},
      :created_at=>{:db_type=>"timestamp without time zone", :default=>nil, :allow_null=>true, :primary_key=>false, :type=>:datetime, :ruby_default=>nil},
      :count=>{:db_type=>"integer", :default=>nil, :allow_null=>true, :primary_key=>false, :type=>:integer, :ruby_default=>nil},
      :cash=>{:db_type=>"double precision", :default=>nil, :allow_null=>true, :primary_key=>false, :type=>:float, :ruby_default=>nil},
      :title => {:db_type=>"character varying(50)", :default=>nil, :allow_null=>true, :primary_key=>false, :type=>:string, :ruby_default=>nil, :max_length=>50},
      :is_admin => {:db_type=>"boolean", :default=>nil, :allow_null=>true, :primary_key=>false, :type=>:boolean, :ruby_default=>nil},
      :place => {:db_type=>"text", :default=>nil, :allow_null=>false, :primary_key=>false, :type=>:string, :ruby_default=>nil}
    }

    if adapter == 'sqlite'
      schema[:name] = {:db_type=>"text", :default=>nil, :allow_null=>true, :primary_key=>false, :type=>:string, :ruby_default=>nil}
    else
      schema[:name] = {:db_type=>"text", :default=>nil, :allow_null=>true, :primary_key=>false, :type=>:string, :ruby_default=>nil}
    end

    schema.each_pair do |field_name, attrs|
      expect(db_fields[field_name].without(:oid)).to eq(attrs)
    end

    # Also check if volt can decode these back to volt field declarations
    klass_and_db_opts = {
      created_at: [[Time, NilClass], {}],
      title: [[String, NilClass], size: 50],
      place: [[String], {}],
      count: [[Fixnum, NilClass], {}],
      cash: [[Float, NilClass], {}],
      is_admin: [[Volt::Boolean, NilClass], {}]
    }

    klass_and_db_opts.each_pair do |field_name, klasses_and_db_opts|
      expect_klasses, expect_db_opts = klasses_and_db_opts

      klasses, db_opts = Volt::Sql::Helper.klasses_and_options_from_db(db_fields[field_name])

      expect(expect_klasses).to eq(klasses)
      expect(expect_db_opts).to eq(db_opts)
    end

  end

  it 'should create migrations when a field changes' do
    class SampleModel3 < Volt::Model
      temporary
      field :some_num, Fixnum
    end

    # Calling db runs pending reconciles
    db_adapter.db
    expect(db.tables).to include(:sample_model3s)

    Volt::RootModels.remove_model_class(SampleModel3)
    Object.send(:remove_const, :SampleModel3)

    db_adapter.skip_reconcile do
      class SampleModel3 < Volt::Model
        temporary
        field :some_num, String
      end
    end

    reconcile = Volt::Sql::TableReconcile.new(db, SampleModel3)

    allow(reconcile.field_updater).to receive(:generate_and_run)
    .with(
      "column_change_sample_model3s_some_num",
      "set_column_type :sample_model3s, :some_num, String, {:allow_null=>true, :text=>true}",
      "set_column_type :sample_model3s, :some_num, Fixnum, {:allow_null=>true}"
    ).and_return(nil)

    reconcile.run
  end

  it 'should create a migration when a field is removed' do
    class SampleModel4 < Volt::Model
      temporary
      field :some_num, Fixnum
    end

    # Calling db runs pending reconciles
    db_adapter.db
    expect(db.tables).to include(:sample_model4s)

    Volt::RootModels.remove_model_class(SampleModel4)
    Object.send(:remove_const, :SampleModel4)

    db_adapter.skip_reconcile do
      class SampleModel4 < Volt::Model
        temporary
      end
    end

    reconcile = Volt::Sql::TableReconcile.new(db, SampleModel4)

    expect(reconcile.field_updater).to receive(:generate_and_run)
    .with(
      "remove_sample_model4s_some_num",
      "drop_column :sample_model4s, :some_num",
      "add_column :sample_model4s, :some_num, Fixnum, {:allow_null=>true}"
    )

    reconcile.run
  end

  it 'should create a migration to change the allow null status' do
    class SampleModel5 < Volt::Model
      temporary
      field :some_num, Fixnum
    end

    # Calling db runs pending reconciles
    db_adapter.db
    expect(db.tables).to include(:sample_model5s)

    Volt::RootModels.remove_model_class(SampleModel5)
    Object.send(:remove_const, :SampleModel5)

    db_adapter.skip_reconcile do
      class SampleModel5 < Volt::Model
        temporary
        field :some_num, Fixnum, nil: false
      end
    end

    reconcile = Volt::Sql::TableReconcile.new(db, SampleModel5)

    expect(reconcile.field_updater).to receive(:generate_and_run)
    .with(
      "column_change_sample_model5s_some_num",
      "set_column_not_null :sample_model5s, :some_num",
      "set_column_allow_null :sample_model5s, :some_num"
    )

    reconcile.run
  end
end
