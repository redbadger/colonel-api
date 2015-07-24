describe 'Linting' do
  it 'Ruby code passes linting' do
    expect(system('rubocop')).to be true
  end
end
