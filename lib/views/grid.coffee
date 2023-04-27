{View, $} = require 'atom-space-pen-views'

module.exports =
class GridView extends View
  readonly: false

  constructor:  ()->
    super

  initialize: ->
    $(window).resize => @fixSizes() # Memory leak!!!
    @handleScrollEvent()

  getTitle: -> @title ? 'untitled'

  @content: ->
    @div class: 'quick-query-grid' , =>
      @table class: 'table quick-query-grid-corner', =>
        @thead => (@tr => (@th outlet: 'corner', =>
          @span class: 'hash', '#'
          @button class: 'btn icon icon-pencil',title: 'Apply changes' , outlet: 'applyButton' , ''
        ))
      @table class: 'table quick-query-grid-numbers', outlet: 'numbers' ,=>
      @table class: 'table quick-query-grid-header', outlet: 'header', =>
      @div class: 'quick-query-grid-table-wrapper', outlet: 'tableWrapper' , =>
        @table class: 'quick-query-grid-table table', outlet: 'table', tabindex: -1 , ''
      @div class: 'edit-long-text', outlet: 'editLongText' , ''

  showRows: (@rows, @fields, @readonly, done)->
    @removeClass('changed confirmation')
    @attr 'data-allow-edition' , =>
      if not @readonly then 'yes' else null
    @keepHidden = false
    thead = document.createElement('thead')
    tr = document.createElement('tr')
    for field in @fields
      th = document.createElement('th')
      th.textContent = field.name
      tr.appendChild(th)
    thead.appendChild(tr)
    @header.html(thead)
    numbersBody = document.createElement('tbody')
    @numbers.html(numbersBody)
    tbody = document.createElement('tbody')
    # for row,i in @rows
    @canceled = false
    @forEachChunk @rows , done , (row,i) =>
      array_row = Array.isArray(row)
      tr = document.createElement('tr')
      td = document.createElement('td')
      td.textContent = i+1
      tr.appendChild td
      numbersBody.appendChild(tr)
      tr = document.createElement('tr')
      for field,j in @fields
        td = document.createElement('td')
        row_value = if array_row then row[j] else row[field.name]
        if row_value?
          td.setAttribute 'data-original-value' , row_value
          td.textContent = row_value
          @showInvisibles(td)
        else
          td.dataset.originalValueNull = true
          td.classList.add 'null'
          td.textContent = 'NULL'
        td.addEventListener 'mousedown', (e)=>
          @table.find('td').removeClass('selected')
          e.currentTarget.classList.add('selected')
        if not @readonly
          td.addEventListener 'dblclick', (e)=>
            col = e.pageX - $(e.currentTarget).offset().left - 8
            @editRecord(e.currentTarget, col)
        tr.appendChild td
      tbody.appendChild(tr)
    @table.html(tbody)

  copyAll: ->
    if @rows? && @fields?
      if Array.isArray(@rows[0])
        fields = @fields.map (field,i) ->
          label: field.name
          value: (row)-> row[i]
      else
        fields = @fields.map (field) -> field.name
      rows = @rows.map (row) ->
        simpleRow = JSON.parse(JSON.stringify(row))
        simpleRow
      json2csv del: "\t", data: rows , fields: fields , defaultValue: '' , (err, csv)->
        if (err)
          console.log(err)
        else
          atom.clipboard.write(csv)

  saveCSV: ->
    if @rows? && @fields?
      atom.getCurrentWindow().showSaveDialog title: 'Save Query Result as CSV', defaultPath: process.cwd(), (filepath) =>
        if filepath?
          if Array.isArray(@rows[0])
            fields = @fields.map (field,i) ->
              label: field.name
              value: (row)-> row[i]
          else
            fields = @fields.map (field) -> field.name
          rows = @rows.map (row) ->
            simpleRow = JSON.parse(JSON.stringify(row))
            simpleRow[field] ?= '' for field in fields
            simpleRow
          json2csv  data: rows , fields: fields , defaultValue: '' , (err, csv)->
            if (err)
              console.log(err)
            else
              fs.writeFile filepath, csv, (err)->
                if (err) then console.log(err) else console.log('file saved')


  showInvisibles: (td)->
    td.innerHTML = td.innerHTML
      .replace(/\r\n/g,'<span class="crlf"></span>')
      .replace(/\n/g,'<span class="lf"></span>')
      .replace(/\r/g,'<span class="cr"></span>')
    s.textContent = "\r\n" for s in td.getElementsByClassName("crlf")
    s.textContent = "\n" for s in td.getElementsByClassName("lf")
    s.textContent = "\r" for s in td.getElementsByClassName("cr")


  forEachChunk: (array,done,fn)->
    chuncksize = 100
    index = 0
    doChunk = ()=>
      cnt = chuncksize
      while cnt > 0 && index < array.length
        fn.call(@,array[index], index, array)
        ++index
        cnt--
      if index < array.length
        @loop = setTimeout(doChunk, 1)
      else
        @loop = null
        done?()
    doChunk()

  isTableFocused: -> @table.is(':focus')
  isEditingLongText: ()-> @hasClass('editing-long-text')

  focusTable: ->
    @table.focus()

  getCursor: ->
    td = @selectedTd()
    return null unless td
    tr = td.parentNode
    x = [tr.children...].indexOf(td)
    y = [tr.parentNode.children...].indexOf(tr)
    [x,y]

  setCursor: (x,y)->
    td1 = @selectedTd()
    td2 = @getTd(x, y)
    if td && td1 != td2
      td1.classList.remove('selected')
      td2.classList.add('selected')

  stopLoop: ->
    if @loop?
      clearTimeout(@loop)
      @loop = null
      @canceled = true

  rowsStatus: ->
    table = @element.querySelector('.quick-query-grid-table')
    added = table.querySelectorAll('tr.added').length
    status = (@rows.length + added).toString()
    status += if status == '1' then ' row' else ' rows'
    if @canceled
      tr_count = table.querySelectorAll('tr').length
      status = "#{tr_count} of #{status}"
    status += ",#{added} added" if added > 0
    modified = table.querySelectorAll('tr.modified').length
    status += ",#{modified} modified" if modified > 0
    removed = table.querySelectorAll('tr.removed').length
    status += ",#{removed} deleted" if removed > 0
    @toggleClass('changed',added+modified+removed>0)
    status

  copy: ->
    td = @selectedTd()
    atom.clipboard.write(td.textContent) if td

  paste: ->
    if not @readonly
      td = @selectedTd()
      val = atom.clipboard.read()
      @setCellVal(td,val)

  moveSelection: (direction)->
    td1 = @selectedTd()
    return if td1.classList.contains('editing')
    tr = td1.parentNode
    [x, y] = @getCursor()
    td2 = switch direction
      when 'right' then td1.nextElementSibling
      when 'left'  then td1.previousElementSibling
      when 'up'    then tr.previousElementSibling?.children[x]
      when 'down'  then tr.nextElementSibling?.children[x]
      when 'page-up', 'page-down'
        trs = tr.parentNode.children
        page_size = Math.floor(@tableWrapper.height()/td1.offsetHeight)
        tr_index = if direction == 'page-up'
          Math.max(0, y - page_size)
        else
          Math.min(trs.length-1, y + page_size)
        trs[tr_index].children[cursor.x]
    if td2
      td1.classList.remove('selected')
      td2.classList.add('selected')
      @scrollToTd(td2)

  scrollToTd: (td)->
    table = @tableWrapper.offset()
    table.bottom = table.top + @tableWrapper.height()
    table.right = table.left + @tableWrapper.width()
    cell = td.getBoundingClientRect()
    if cell.top < table.top
      @tableWrapper.scrollTop(@tableWrapper.scrollTop() - table.top + cell.top)
    if cell.bottom > table.bottom
      @tableWrapper.scrollTop(@tableWrapper.scrollTop() + cell.bottom - table.bottom + 1.5 * cell.height)
    if cell.left < table.left
      @tableWrapper.scrollLeft(@tableWrapper.scrollLeft() - table.left + cell.left)
    if cell.right > table.right
      @tableWrapper.scrollLeft(@tableWrapper.scrollLeft() + cell.right - table.right + 1.5 * cell.width)

  editRecord: (td, cursor)->
    if td.getElementsByTagName("atom-text-editor").length == 0
      td.classList.add('editing')
      editor = document.createElement('atom-text-editor')
      editor.classList.add('editor')
      editor.setAttribute('mini','mini');
      textEditor = editor.getModel()
      textEditor.setText(td.textContent) unless td.classList.contains('null')
      textEditor.getBuffer().clearUndoStack()
      if textEditor.getLineCount() == 1
        td.innerHTML = ''
        td.appendChild(editor)
        if cursor?
          charWidth = textEditor.getDefaultCharWidth()
          textEditor.setCursorBufferPosition([0, Math.floor(cursor/charWidth)])
        textEditor.onDidChangeCursorPosition (e) =>
          if editor.offsetWidth > @tableWrapper.width() #center cursor on screen
            td = editor.parentNode
            tr = td.parentNode
            charWidth =  textEditor.getDefaultCharWidth()
            column = e.newScreenPosition.column
            trleft = -1 * $(tr).offset().left
            tdleft =  $(td).offset().left
            width = @tableWrapper.width() / 2
            left = trleft + tdleft - width
            if Math.abs(@tableWrapper.scrollLeft() - (left + column * charWidth)) > width
              @tableWrapper.scrollLeft(left + column * charWidth)
        editor.addEventListener 'blur', (e) =>
          editor = e.currentTarget
          td = editor.parentNode
          val = editor.getModel().getText()
          @setCellVal(td,val)
      else
        editor = document.createElement('atom-text-editor')
        editor.classList.add('editor')
        textEditor = editor.getModel()
        textEditor.setText(td.textContent)
        textEditor.update({autoHeight: false})
        textEditor.getBuffer().clearUndoStack()
        @addClass('editing-long-text')
        @editLongText.html(editor)
        editor.addEventListener 'blur', (e) =>
          editor = e.currentTarget
          @removeClass('editing-long-text')
          td = $('.editing',@table)[0]
          val = editor.getModel().getText()
          @setCellVal(td,val)
      $(editor).focus()


  editSelected: ->
    td = @selectedTd()
    if td? && !@readonly
      editors = td.getElementsByTagName("atom-text-editor")
      if editors.length == 0
        @editRecord(td)
      else
        val = editors[0].getModel().getText()
        @setCellVal(td,val)
        @table.focus()

  setCellVal: (td,text)->
    td.classList.remove('editing','null')
    tr = td.parentNode
    #$tr.hasClass('status-removed') return
    td.textContent = text
    @showInvisibles(td)
    @fixSizes()
    if tr.classList.contains('added')
      td.classList.remove('default')
      td.classList.add('status-added')
    else if text != td.getAttribute('data-original-value')
        tr.classList.add('modified')
        td.classList.add('status-modified')
    else
      td.classList.remove('status-modified')
      if tr.querySelector('td.status-modified') == null
        tr.classList.remove('modified')
    @trigger('quickQuery.rowStatusChanged',[tr])

  insertRecord: ->
    td = document.createElement 'td'
    tr = document.createElement 'tr'
    number = @numbers.find('tr').length + 1
    td.textContent = number
    tr.appendChild(td)
    @numbers.children('tbody').append(tr)
    tr = document.createElement 'tr'
    tr.classList.add 'added'
    @header.find("th").each =>
      td = document.createElement 'td'
      td.addEventListener 'mousedown', (e)=>
        @table.find('td').removeClass('selected')
        e.currentTarget.classList.add('selected')
      td.classList.add('default')
      td.addEventListener 'dblclick', (e) =>
        col = e.pageX - $(e.currentTarget).offset().left - 8
        @editRecord(e.currentTarget, col)
      tr.appendChild(td)
    @table.find('tbody').append(tr)
    @fixSizes() if number == 1
    @tableWrapper.scrollTop -> this.scrollHeight
    @trigger('quickQuery.rowStatusChanged',[tr])

  selectedTd: -> @element.querySelector('td.selected')
  getTd: (x,y) -> @element.querySelector(".quick-query-grid-table tr:nth-child(#{y}) td:nth-child(#{x})")

  deleteRecord: ->
    td = @selectedTd()
    if not @readonly && td?
      tr = td.parentNode
      tr.classList.remove('modified')
      for td1 in tr.children
        td1.classList.remove('status-modified')
      tr.classList.add('status-removed','removed')
      @trigger('quickQuery.rowStatusChanged',[tr])

  undo: ->
    td = @selectedTd()
    if td?
      tr = td.parentNode
      if tr.classList.contains('removed')
        tr.classList.remove('status-removed','removed')
      else if tr.classList.contains('added')
        td.classList.remove('null')
        td.classList.add('default')
        td.textContent = ''
      else
        if td.dataset.originalValueNull
          td.classList.add('null')
          td.textContent = 'NULL'
        else
          value = td.getAttribute('data-original-value')
          td.classList.remove('null')
          td.textContent = value
          @showInvisibles(td)
        td.classList.remove('status-modified')
        if tr.querySelector('td.status-modified') == null
          tr.classList.remove('modified')
      @trigger('quickQuery.rowStatusChanged',[tr])

  setNull: ->
    td = @selectedTd()
    if not @readonly && td? && !td.classList.contains('null')
      tr = td.parentNode
      #$tr.hasClass('status-removed') return
      td.textContent = 'NULL'
      td.classList.add('null')
      if tr.classList.contains('added')
        td.classList.remove('default')
        td.classList.add('status-added')
      else if td.dataset.originalValueNull
        td.classList.remove('status-modified')
        if tr.querySelector('td.status-modified') == null
          tr.classList.remove('modified')
      else
        tr.classList.add('modified')
        td.classList.add('status-modified')
      @trigger('quickQuery.rowStatusChanged',[tr])

  getChanges: ->
    allChanges = []
    @table.find('tbody tr').each (i,tr)=>
      changes = []
      rowChanges = null
      apply = () => @applyChangesToRow(tr, i)
      if tr.classList.contains('modified')
        row = @rows[i]
        for td,j in tr.childNodes
          change = { field: @fields[j],  value: row[j], apply }
          if td.classList.contains('status-modified')
            change.newValue = if td.classList.contains('null') then null else td.textContent
          changes.push change
        rowChanges = {type: 'modified', changes}
      else if tr.classList.contains('added')
        for td,j in tr.childNodes
          change = { field: @fields[j], apply }
          unless td.classList.contains('default')
            change.value = if td.classList.contains('null') then null else td.textContent
          changes.push change
        rowChanges = {type: 'added', changes}
        allChanges.push(rowChanges)
      else if tr.classList.contains('status-removed')
        row = @rows[i]
        changes = @fields.map (field,j)-> {field: field, value: row[j], apply}
        rowChanges = {type: 'added', changes}
      allChanges.push(rowChanges) if rowChanges
    return allChanges

  applyChangesToRow: (tr,index)->
    tbody = tr.parentNode
    values = for td in tr.children
      if td.classList.contains('null') then null else td.textContent
    if tr.classList.contains('status-removed')
      @rows.splice(index,1)
      tbody.removeChild(tr)
      @numbers.children('tbody').children('tr:last-child').remove()
    else if tr.classList.contains('added')
      @rows.push values
      tr.classList.remove('added')
      for td in tr.children
        td.classList.remove('status-added','default')
        td.setAttribute 'data-original-value', td.textContent
        td.dataset.originalValueNull = td.classList.contains('null')
    else if tr.classList.contains('modified')
      @rows[index] = values
      tr.classList.remove('modified')
      for td in tr.children
        td.classList.remove('status-modified')
        td.setAttribute 'data-original-value', td.textContent
        td.dataset.originalValueNull = td.classList.contains('null')
    @trigger('quickQuery.rowStatusChanged',[tr])

  fixSizes: ->
    row_count = @table.find('tbody tr').length
    if row_count > 0
      tds = @table.find('tbody tr:first').children()
      @header.find('thead tr').children().each (i, th) =>
        td = tds[i]
        thw = th.offsetWidth
        tdw = td.offsetWidth
        w = Math.max(tdw,thw)
        td.style.minWidth = w+"px"
        th.style.minWidth = w+"px"
    else
      @table.width(@header.width())
    @applyButton.toggleClass('tight',row_count < 100)
    @applyButton.toggleClass('x2',row_count < 10)
    @fixScrolls()

  fixScrolls: ->
    handlerHeight = 5
    headerHeght = @header.height()
    if @numbers.find('tr').length > 0
      numbersWidth = @numbers.width()
      @corner.css width: numbersWidth
    else
      numbersWidth = @corner.outerWidth()
    @tableWrapper.css left: numbersWidth , top: (headerHeght + handlerHeight)
    scroll = handlerHeight + headerHeght  - @tableWrapper.scrollTop()
    @numbers.css top: scroll
    scroll = numbersWidth - @tableWrapper.scrollLeft()
    @header.css left: scroll


  handleScrollEvent: ->
    @tableWrapper.scroll (e) =>
      handlerHeight = 5
      scroll = $(e.target).scrollTop() - handlerHeight - @header.height()
      @numbers.css top: (-1*scroll)
      scroll = $(e.target).scrollLeft() - @numbers.width()
      @header.css left: -1*scroll

  onRowStatusChanged: (callback)->
    @bind 'quickQuery.rowStatusChanged', (e,row)-> callback(row)

  # Tear down any state and detach
  destroy: ->
    # @element.remove()
