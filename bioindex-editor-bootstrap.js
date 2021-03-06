/*global $, mw */
// bootstrap the editor for [[Wikipedia:Indeks biografii]] with minimal code
$( function() {
	if($('.bioindex-entry').length === 0) {
		return;
	}

	mw.loader.using('jquery.spinner', function() {
		function loadHandler(e) {
			if(e.type === 'keypress' && e.which !== 13 && e.which !== 32) {
				return; // handle enter and space
			}
			var $editlink = $(this);
			var $spinner = $.createSpinner().css('margin-left', '1em');
			$editlink.after($spinner);
			
			mw.loader.using('ext.gadget.bioindex-editor', function() {
				$spinner.remove();
				$editlink.trigger('click');
			});
			
			$('#mw-content-text').off('click keypress', '.bioindex-entry .bioindex-edit a', loadHandler);
			e.preventDefault();
		}

		$('#mw-content-text').on('click keypress', '.bioindex-entry .bioindex-edit a', loadHandler);
	});
} );
