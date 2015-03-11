require "w2ui_utils/version"

module W2uiUtils
  module W2uiGrid
    def self.included(base)
      base.class_eval do
        delegate :params, :h, :l, :link_to, to: :@view
      end
    end

    # Constructor
    def initialize(view, collection, controller = nil)
      @view = view
      @collection = collection
      @controller = controller

      @record_class = collection.is_a?(Class) ? collection : collection.first.class
      @table_name = @record_class.table_name
    end

    # Convert to JSON
    def as_json(options = {})
      {
        status: options['status'] || 'success',
        total: records_count,
        records: records
      }
    end

    # Get real records count of grid collection
    def records_count
      cached_collection.count
    end

    # Default sorting
    def sort_default
      ''
    end

    # Get all records of collection for grid
    def get_records
      return error_response unless is_get_records_request?
      as_json
    end

    # Save all changed records of grid to collection
    def save_records
      return error_response unless is_save_records_request?
      if params[:changes]
        params[:changes].each_value do |changed|
          fields = changed.keys
          record = @record_class.find(changed[fields.delete('recid')])
          if record.present?
            fields.each do |field|
              table, column = get_table_and_column field
              obj = if table == @table_name
                record
              elsif record.respond_to?(table.to_sym)
                record.send("#{table}")
              end
              obj.send("#{column}=", changed[field]) if obj and obj.respond_to?(column.to_sym)
            end
            return error_response unless record.save
          end
        end
      end
      succes_response
    end

    # Delete all selected records of grid to collection
    def delete_records
      return error_response unless is_delete_records_request?
      if params[:selected]
        params[:selected].each_value do |id|
          record = @record_class.find id
          record.destroy if record.present?
        end
      end
      succes_response
    end

    protected

    # Succes json (hash) response
    def succes_response
      {
        status: 'success'
      }
    end

    # Error json (hash) response
    def error_response(message = 'error')
      {
        status: 'error',
        message: message
      }
    end

    def is_get_records_request?
      'get-records' == params[:cmd]
    end

    def is_save_records_request?
      'save-records' == params[:cmd]
    end

    def is_delete_records_request?
      'delete-records' == params[:cmd]
    end

    private

    def get_table_and_column(field)
      /^(?:(\w+)__(\w+))$/.match(field)[1..2]
    end

    def cached_collection
      @cached_collection ||= fetch_collection
    end

    def records
      cached_collection.map do |objekt|
        data_proc.call objekt
      end
    end

    def fetch_collection
      @collection.where(search).order(sort).limit(limit).offset(offset)
    end

    def limit
      params[:limit]
    end

    def offset
      params[:offset]
    end

    def sort
      if params[:sort]
        params[:sort].map do |_, order|
          table, column = get_table_and_column order['field']
          "#{table}.#{column} #{order['direction']}" if table and column
        end.join(', ')
      else
        sort_default
      end
    end

    def search
      if params[:search]
        params[:search].map do |_, search|
          table, column = get_table_and_column search['field']
          val = case search['type']
          when 'date'
            case search['operator']
            when 'is' then "between '#{search['value'].to_date.beginning_of_day}' and '#{search['value'].to_date.end_of_day}'"
            when 'between' then "between '#{search['value'].first.to_date.beginning_of_day}' and '#{search['value'].last.to_date.end_of_day}'"
            end
          when 'text'
            case search['operator']
            when 'is' then "= '#{search['value']}'"
            when 'begins' then "like '#{search['value']}%'"
            when 'contains' then "like '%#{search['value']}%'"
            when 'ends' then "like '%#{search['value']}'"
            end
          when 'int'
            case search['operator']
            when 'is' then "= #{search['value']}"
            when 'in' then "in (#{search['value'].join(',')})"
            when 'not in' then "not in (#{search['value'].join(',')})"
            when 'between' then "between #{search['value'].first} and #{search['value'].last}"
            end
          end
          "#{table}.#{column} #{val}" if val
        end.join " #{params[:searchLogic]} "
      end
    end
  end
end
