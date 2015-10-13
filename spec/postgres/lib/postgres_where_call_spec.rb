require 'spec_helper'

describe Volt::Sql::WhereCall do
  it 'should replay the ast' do
    ast = ["c", "ident", "name"]

    name_double = double('name')
    ident = double('ident')
    expect(ident).to receive(:name).and_return(name_double)
    result = Volt::Sql::WhereCall.new(ident).call(ast)

    expect(result).to eq(name_double)
  end

  it 'should replay the ast with nested' do
    ast = ["c", ["c", "ident", "lat"], ">", 80]

    ident = double('ident')
    lat = double('lat')
    expect(ident).to receive(:lat).and_return(lat)

    final = double('final')
    expect(lat).to receive(:>).with(80).and_return(final)

    result = Volt::Sql::WhereCall.new(ident).call(ast)

    expect(result).to eq(final)
  end

  it 'should replay with nested and logical operators' do
    ast = [
      "c",
      ["c", ["c", "ident", "lat"], ">", 80],
      '&',
      ["c", ["c", "ident", "lng"], "<", 50]
    ]

    ident = double('ident')
    lat = double('lat')
    expect(ident).to receive(:lat).and_return(lat)

    lng = double('lng')
    expect(ident).to receive(:lng).and_return(lng)

    left = double('left')
    expect(lat).to receive(:>).with(80).and_return(left)

    right = double('right')
    expect(lng).to receive(:<).with(50).and_return(right)

    final = double('final')
    expect(left).to receive(:&).with(right).and_return(final)

    result = Volt::Sql::WhereCall.new(ident).call(ast)

    expect(result).to eq(final)

  end
end
