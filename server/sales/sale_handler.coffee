Sale = require './Sale'
User = require '../users/User'
Handler = require '../commons/Handler'
{handlers} = require '../commons/mapping'
mongoose = require 'mongoose'
log = require 'winston'

SaleHandler = class SaleHandler extends Handler
  modelClass: Sale
  editableProperties: []
  postEditableProperties: ['sold']
  jsonSchema: require '../../app/schemas/models/sale.schema'

  makeNewInstance: (req) ->
    sale = super(req)
    sale.set 'seller', req.user._id
    sale.set 'recipient', req.user._id
    sale.set 'created', new Date().toISOString()
    sale

  post: (req, res) ->
    sold = req.body.sold
    seller = req.user._id
    soldOriginal = sold?.original

    Handler = require '../commons/Handler'
    return @sendBadInputError(res) if not Handler.isID(soldOriginal)

    collection = sold?.collection
    return @sendBadInputError(res) if not collection in @jsonSchema.properties.sold.properties.collection.enum

    handler = require('../' + handlers[collection])
    criteria = { 'original': soldOriginal }
    sort = { 'version.major': -1, 'version.minor': -1 }

    handler.modelClass.findOne(criteria).sort(sort).exec (err, soldItem) =>
      gemsOwned = req.user.get('earned')?.gems or 0
      return @sendDatabaseError(res, err) if err
      return @sendNotFoundError(res) unless soldItem
      req.soldItem = soldItem # for safekeeping

      criteria = {
        'sold.original': soldOriginal
        'recipient': seller
      }
      Sale.findOne criteria, (err, sale) =>
        if sale
          @addSaleToUser(req, res)
          return @sendSuccess(res, @formatEntity(req, sale))

        else
          super(req, res)

  onPostSuccess: (req) ->
    @addSaleToUser(req)
    req.user?.saveActiveUser 'sale'

  addSaleToUser: (req) ->
    user = req.user
    sales = user.get('sales') or {}
    sales = _.cloneDeep sales
    item = req.soldItem

    group = switch item.get('kind')
      when 'Item' then 'items'
      when 'Hero' then 'heroes'
      else 'levels'

    original = item.get('original') + ''
    
    #log.info user.get('purchased')
    
    sales[group] ?= []
    unless original in sales[group]
      #- add the sale to the list of sales
      sales[group].push(original+'')
      user.set('sales', sales)

      #- Add the gems to the user
      sold = user.get('sold') ? 0
      
      sold += item.get('gemsSale')
      user.set('sold', sold)

      user.save()

module.exports = new SaleHandler()
