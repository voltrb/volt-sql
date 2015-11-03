require 'spec_helper'
require_relative 'helpers'

describe Volt::Sql::IndexUpdater do
  let(:db_adaptor) { Volt::DataStore.fetch(volt_app) }
  let(:db) { db_adaptor.db }
  before do
    # Access store, so we trigger cleanup after
    store
  end

  include Volt::Spec::Helpers

  it 'should add indexes' do
    class SampleModelIndexes1 < Volt::Model
      temporary
      field :name, String

      index :name
    end

    reconcile!

    expect(indexes(:sample_model_indexes1s)).to eq(
      {:sample_model_indexes1s_name_index=>{:columns=>[:name], :unique=>false}}
    )
  end

  it 'should drop a removed index' do
    class SampleModelIndexes2 < Volt::Model
      temporary
      field :name, String

      index :name
    end

    reconcile!

    expect(indexes(:sample_model_indexes2s)).to eq(
      {:sample_model_indexes2s_name_index=>{:columns=>[:name], :unique=>false}}
    )

    remove_model(SampleModelIndexes2)

    class SampleModelIndexes2 < Volt::Model
      temporary
      field :name, String
    end

    reconcile!

    expect(indexes(:sample_model_indexes2s)).to eq({})
  end

  it 'should rename an index' do
    class SampleModelIndexes3 < Volt::Model
      temporary
      field :name, String

      index :name, name: :index_for_name
    end

    reconcile!

    expect(indexes(:sample_model_indexes3s)).to eq(
      {:index_for_name=>{:columns=>[:name], :unique=>false}}
    )

    remove_model(SampleModelIndexes3)

    class SampleModelIndexes3 < Volt::Model
      temporary
      field :name, String

      index :name, name: :name_index_for_name, unique: true
    end

    expect(SampleModelIndexes3.indexes).to eq(
      {:name_index_for_name=>{:unique=>true, :columns=>[:name]}}
    )

    reconcile!

    expect(indexes(:sample_model_indexes3s)).to eq(
      {:name_index_for_name=>{:columns=>[:name], :unique=>true}}
    )
  end
end
